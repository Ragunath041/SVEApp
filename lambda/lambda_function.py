import json
import boto3
import csv
from io import StringIO
from datetime import datetime
from boto3.dynamodb.conditions import Attr, Key
import re

# ─────────────────────────────────────────────
# S3 Configuration (CSV)
# ─────────────────────────────────────────────
BUCKET_NAME = 'bitsexamapp'
ANSWERS_BUCKET_NAME = 'wilp-fr-model'
BITS_EXAM_PATH = 'student_details/BITS-exam.csv'
EXAM_DETAILS_PATH = 'exam_details/ExamDetails.csv'

# ─────────────────────────────────────────────
# DynamoDB Configuration
# ─────────────────────────────────────────────
dynamodb = boto3.resource('dynamodb')
TIMINGS_TABLE_NAME = 'bits-exam-center-timings'
ATTENDANCE_TABLE_NAME = 'bits-attendance-details'

HEADERS = {
    'Content-Type': 'application/json',
    'Access-Control-Allow-Origin': '*'
}

def response(status_code, body):
    return {
        'statusCode': status_code,
        'headers': HEADERS,
        'body': json.dumps(body)
    }

# ─────────────────────────────────────────────
# Entry Point
# ─────────────────────────────────────────────
def lambda_handler(event, context):
    try:
        # Check if it is an S3 event trigger
        if 'Records' in event and event['Records'] and event['Records'][0].get('eventSource') == 'aws:s3':
            return handle_s3_upload_event(event)
                # Handle CORS preflight (OPTIONS) and POST requests
        http_method = 'GET'
        if 'requestContext' in event and 'http' in event['requestContext']:
            http_method = event['requestContext']['http'].get('method', 'GET')
        elif 'httpMethod' in event:
            http_method = event.get('httpMethod', 'GET')

        if http_method == 'OPTIONS':
            return {
                'statusCode': 200,
                'headers': {
                    'Access-Control-Allow-Origin': '*',
                    'Access-Control-Allow-Headers': 'Content-Type,X-Amz-Date,Authorization,X-Api-Key,X-Amz-Security-Token',
                    'Access-Control-Allow-Methods': 'GET,POST,OPTIONS'
                },
                'body': ''
            }

        # Check if POST request
        if http_method == 'POST':
            body_str = event.get('body', '')
            if event.get('isBase64Encoded', False):
                import base64
                body_str = base64.b64decode(body_str).decode('utf-8')
            
            payload = {}
            if body_str:
                payload = json.loads(body_str)
            
            action = payload.get('action')
            if action == 'saveScannedQR':
                return handle_save_scanned_qr(payload)
            else:
                return response(400, {'success': False, 'error': f'Unsupported POST action: {action}'})


        params = event.get('queryStringParameters') or {}
        action = params.get('action')

        if action == 'markIncident':
            return handle_mark_incident(
                params.get('studentId'),
                params.get('courseCode'),
                params.get('examDate'),
                params.get('session')
            )

        if action == 'allStudents':
            return handle_all_student_ids()

        if action == 'centerExams':
            return handle_center_exams(params.get('centre'), params.get('date'))

        if action == 'sessionHistory':
            return handle_session_history(params.get('centre'))

        if action == 'attendanceStatus':
            return handle_attendance_status(
                params.get('centre') or params.get('center'),
                params.get('courseCode'),
                params.get('session'),
                params.get('date') or params.get('examDate')
            )

        if params.get('studentId'):
            return handle_student_exam_details(params['studentId'])

        if params.get('courseCode'):
            return handle_course_name_lookup(event, context)

        return handle_student_ids_by_date(event, context)

    except Exception as e:
        print(f'Unhandled error: {e}')
        return response(500, {'success': False, 'error': str(e)})

# ─────────────────────────────────────────────
# Save Scanned Student QR Code Handler
# ─────────────────────────────────────────────
def handle_save_scanned_qr(payload):
    try:
        bits_id = payload.get('bitsId', '').strip().lower()
        if not bits_id:
            return response(400, {'success': False, 'error': 'Missing bitsId'})

        # Extract and clean values for the composite Sort Key
        timing_raw = payload.get('examTiming', '')
        date_raw = payload.get('examDate', '')
        
        # Remove all non-digits (e.g. "09:30 - 12:00" -> "09301200", "2026-07-27" -> "20260727")
        timing_digits = re.sub(r'\D', '', timing_raw)
        date_digits = re.sub(r'\D', '', date_raw)
        
        # Composite unique sort key: scannedId
        # e.g., dummyuser1_0930120020260727
        scanned_id_val = f"{bits_id}_{timing_digits}{date_digits}"
        
        # Put item in Bits-Supervisor-Confirmation table
        table = dynamodb.Table('Bits-Supervisor-Confirmation')
        
        # Construct item dictionary
        item = {
            'bitsId': bits_id,
            'scannedId': scanned_id_val,  # Enforces uniqueness per student exam session
            'name': payload.get('name', '').strip(),
            'organization': payload.get('organization', '').strip(),
            'center': payload.get('center', '').strip(),
            'courseCode': payload.get('courseCode', '').strip(),
            'courseName': payload.get('courseName', '').strip(),
            'examDate': date_raw.strip(),
            'examTiming': timing_raw.strip(),
            'scannedtime': payload.get('scannedtime', '').strip(),  # Stores actual device scan time
            'scanneddate': payload.get('scanneddate', '').strip(),  # Stores actual device scan date
            'supervisorId': payload.get('supervisorId', '').strip()
        }
        
        table.put_item(Item=item)
        return response(200, {'success': True, 'message': 'Student verification details saved successfully'})
    except Exception as e:
        print(f'Error in handle_save_scanned_qr: {e}')
        return response(500, {'success': False, 'error': str(e)})


# ─────────────────────────────────────────────
# Mark Incident Handler
# ─────────────────────────────────────────────
def handle_mark_incident(student_id, course_code, exam_date, session):
    try:
        if not all([student_id, course_code, exam_date]):
            return response(400, {'success': False, 'error': 'Missing studentId, courseCode, or examDate'})

        sid_lower = student_id.strip().lower()
        clean_course = course_code.strip().upper().replace(' ', '')
        
        # 1. Update DynamoDB
        table = dynamodb.Table(ATTENDANCE_TABLE_NAME)
        filter_expr = Attr('courseCode').eq(clean_course) & Attr('examDate').eq(exam_date)
        if session:
            filter_expr = filter_expr & Attr('sessionType').eq(session)

        res = table.query(KeyConditionExpression=Key('bitsId').eq(sid_lower), FilterExpression=filter_expr)
        items = res.get('Items', [])
        
        if items:
            attendance_id = items[0]['attendanceId']
            table.update_item(
                Key={'bitsId': sid_lower, 'attendanceId': attendance_id},
                UpdateExpression='SET finished = :code',
                ExpressionAttributeValues={':code': '99:99:99'}
            )

        # 2. Record separate incident file in S3
        s3 = boto3.client('s3')
        incident_data = {
            'studentId': student_id,
            'courseCode': course_code,
            'examDate': exam_date,
            'session': session,
            'reason': 'Exam locked due to browsing tolerance',
            'timestamp': datetime.now().isoformat()
        }
        
        file_key = f'bits-incidents/{student_id}_{exam_date}_{session or "GEN"}.json'
        s3.put_object(
            Bucket=BUCKET_NAME,
            Key=file_key,
            Body=json.dumps(incident_data),
            ContentType='application/json'
        )

        return response(200, {'success': True, 'message': 'Marked incident and recorded file'})
    except Exception as e:
        print(f'Error in markIncident: {e}')
        return response(500, {'success': False, 'error': str(e)})

# ─────────────────────────────────────────────
# Student Exam Details Handler (CSV VERSION)
# ─────────────────────────────────────────────
def handle_student_exam_details(student_id):
    try:
        s3 = boto3.client('s3')
        student_id = student_id.strip().upper()

        # 1. Load ExamDetails Map
        exam_resp = s3.get_object(Bucket=BUCKET_NAME, Key=EXAM_DETAILS_PATH)
        exam_content = exam_resp['Body'].read().decode('utf-8')
        exam_reader = csv.reader(StringIO(exam_content))
        exam_headers = [h.strip().upper() for h in next(exam_reader)]
        
        cc_col = next((i for i, h in enumerate(exam_headers) if 'COURSE' in h and 'CODE' in h), None)
        type_col = next((i for i, h in enumerate(exam_headers) if 'EXAM' in h and 'TYPE' in h), None)

        exam_details_map = {}
        for row in exam_reader:
            if cc_col is not None and len(row) > cc_col:
                code = row[cc_col].strip().upper().replace(' ', '')
                etype = row[type_col].strip() if (type_col is not None and len(row) > type_col) else ''
                exam_details_map[code] = etype

        # 2. Load BITS-exam Student Data
        bits_resp = s3.get_object(Bucket=BUCKET_NAME, Key=BITS_EXAM_PATH)
        bits_content = bits_resp['Body'].read().decode('utf-8')
        bits_reader = csv.reader(StringIO(bits_content))
        bits_headers = [h.strip().upper() for h in next(bits_reader)]

        bits_id_col = next((i for i, h in enumerate(bits_headers) if 'BITS' in h and 'ID' in h), 0)
        name_col = next((i for i, h in enumerate(bits_headers) if h in ('NAME', 'STUDENTNAME')), None)
        centre_col = next((i for i, h in enumerate(bits_headers) if h in ('CENTER', 'CENTRE', 'CENTERCODE')), None)

        today = datetime.now().date()
        date_pattern = re.compile(r'(\d{2}[-/]\d{2}[-/]\d{4})')
        exam_cols = []
        for idx, h in enumerate(bits_headers):
            match = date_pattern.search(h)
            if match:
                try:
                    col_date = datetime.strptime(match.group(1).replace('/', '-'), '%d-%m-%Y').date()
                    if col_date == today:
                        parts = h.split('_')
                        exam_cols.append({'col': idx, 'examNumber': parts[0] if len(parts) >= 3 else 'C1', 'date': match.group(1), 'session': parts[2] if len(parts) >= 3 else 'FN'})
                except: pass

        # 3. Find Student
        for row in bits_reader:
            if len(row) > bits_id_col and row[bits_id_col].strip().upper() == student_id:
                s_name = row[name_col].strip() if name_col is not None and len(row) > name_col else 'Unknown'
                centre = row[centre_col].strip() if centre_col is not None and len(row) > centre_col else 'Unknown'
                timings = get_center_timings(centre)
                
                exams = []
                for ec in exam_cols:
                    if len(row) > ec['col'] and row[ec['col']].strip():
                        raw_c = row[ec['col']].strip().upper()
                        norm_c = raw_c.replace(' ', '')
                        etype = exam_details_map.get(norm_c, '')
                        start, end = get_session_times(timings, ec['session'])
                        exams.append({
                            'courseCode': norm_c,
                            'fullCourseCode': f'{format_course_code(raw_c)}-{etype}' if etype else format_course_code(raw_c),
                            'examType': etype,
                            'session': ec['session'],
                            'date': ec['date'],
                            'examStartTime': start,
                            'examEndTime': end,
                            'examNumber': ec['examNumber']
                        })
                return response(200, {'success': True, 'studentId': student_id, 'studentName': s_name, 'centre': centre, 'exams': exams})

        return response(404, {'success': False, 'error': 'Student not found'})
    except Exception as e:
        return response(500, {'success': False, 'error': str(e)})

# ─────────────────────────────────────────────
# Helper Functions
# ─────────────────────────────────────────────
def format_course_code(code):
    code = code.strip().upper()
    if ' ' in code: return code
    if len(code) > 4: return code[:4] + ' ' + code[4:]
    return code

def get_center_timings(centre_name):
    try:
        table = dynamodb.Table(TIMINGS_TABLE_NAME)
        res = table.get_item(Key={'exam-hall': centre_name.strip()})
        return res.get('Item')
    except: return None

def normalize_time(t):
    if not t: return ''
    parts = str(t).strip().split(':')
    return f'{parts[0]}:{parts[1]}:00' if len(parts) == 2 else str(t).strip()

def get_session_times(timings, session):
    if not timings: return '', ''
    s = session.upper()
    start = normalize_time(timings.get(f'{s}_start', ''))
    end = normalize_time(timings.get(f'{s}_end', ''))
    return start, end

def handle_course_name_lookup(event, context):
    try:
        s3 = boto3.client('s3')
        course_code = event['queryStringParameters'].get('courseCode', '').strip().upper()
        data = s3.get_object(Bucket=BUCKET_NAME, Key=EXAM_DETAILS_PATH)['Body'].read().decode('utf-8')
        reader = csv.reader(StringIO(data))
        headers = [h.strip().upper() for h in next(reader)]
        cc_col = next((i for i, h in enumerate(headers) if 'COURSECODE' in h.replace(' ','')), None)
        cn_col = next((i for i, h in enumerate(headers) if 'COURSENAME' in h.replace(' ','')), None)
        
        for row in reader:
            if len(row) > max(cc_col, cn_col) and row[cc_col].strip().upper() == course_code:
                return response(200, {'success': True, 'courseName': row[cn_col].strip()})
        return response(404, {'success': False, 'error': 'Course not found'})
    except: return response(500, {'success': False, 'error': 'Failed'})

def handle_student_ids_by_date(event, context):
    try:
        s3 = boto3.client('s3')
        params = event.get('queryStringParameters') or {}
        date_str = params.get('date')
        
        data = s3.get_object(Bucket=BUCKET_NAME, Key=BITS_EXAM_PATH)['Body'].read().decode('utf-8')
        reader = csv.reader(StringIO(data))
        headers = [h.strip().upper() for h in next(reader)]
        
        bits_id_col = next((i for i, h in enumerate(headers) if 'BITS' in h and 'ID' in h), 0)
        
        matching_cols = []
        if date_str:
            # Match date in headers
            for i, h in enumerate(headers):
                if date_str in h: matching_cols.append(i)
        
        ids = set()
        for row in reader:
            if len(row) > bits_id_col and row[bits_id_col].strip():
                if not matching_cols or any(len(row) > c and row[c].strip() for c in matching_cols):
                    ids.add(row[bits_id_col].strip().upper())
        
        return response(200, {'success': True, 'studentIds': sorted(list(ids))})
    except: return response(500, {'success': False, 'error': 'Failed'})

def handle_all_student_ids():
    try:
        s3 = boto3.client('s3')
        all_ids = set()

        # 1. Get IDs from master CSV
        try:
            data = s3.get_object(Bucket=BUCKET_NAME, Key=BITS_EXAM_PATH)['Body'].read().decode('utf-8')
            reader = csv.reader(StringIO(data))
            headers = [h.strip().upper() for h in next(reader)]
            bits_id_col = next((i for i, h in enumerate(headers) if 'BITS' in h and 'ID' in h), 0)
            for row in reader:
                if len(row) > bits_id_col and row[bits_id_col].strip():
                    all_ids.add(row[bits_id_col].strip().upper())
        except Exception as csv_err:
            print(f"CSV Load Error: {csv_err}")

        # 2. Get IDs from S3 folder prefixes (History)
        try:
            paginator = s3.get_paginator('list_objects_v2')
            for page in paginator.paginate(Bucket=ANSWERS_BUCKET_NAME, Prefix='Exam-answers/', Delimiter='/'):
                for prefix in page.get('CommonPrefixes', []):
                    # Prefix is 'Exam-answers/STUDENTID/'
                    folder_name = prefix.get('Prefix', '').split('/')[-2]
                    if folder_name and folder_name != 'Exam-answers':
                        all_ids.add(folder_name.upper())
        except Exception as s3_err:
            print(f"S3 Prefix Error: {s3_err}")

        return response(200, {'success': True, 'studentIds': sorted(list(all_ids))})
    except Exception as e:
        print(f"Error in handle_all_student_ids: {e}")
        return response(500, {'success': False, 'error': str(e)})

def handle_center_exams(centre, date_str):
    try:
        s3 = boto3.client('s3')
        if not centre:
            return response(400, {'success': False, 'error': 'Missing centre'})

        # Use provided date or today
        if not date_str:
            date_str = datetime.now().strftime('%d-%m-%Y')

        # Load master CSV
        data = s3.get_object(Bucket=BUCKET_NAME, Key=BITS_EXAM_PATH)['Body'].read().decode('utf-8')
        reader = csv.reader(StringIO(data))
        headers = [h.strip().upper() for h in next(reader)]
        
        centre_col = next((i for i, h in enumerate(headers) if h in ('CENTER', 'CENTRE', 'CENTERCODE')), None)
        if centre_col is None:
            return response(500, {'success': False, 'error': 'Centre column not found'})

        # Find columns matching the date
        matching_cols = []
        for i, h in enumerate(headers):
            if date_str in h:
                parts = h.split('_')
                matching_cols.append({
                    'col': i,
                    'session': parts[2] if len(parts) >= 3 else 'FN'
                })
        
        if not matching_cols:
            return response(200, {'success': True, 'exams': []})

        exams_set = set()
        for row in reader:
            if len(row) > centre_col and row[centre_col].strip().upper() == centre.strip().upper():
                for mc in matching_cols:
                    if len(row) > mc['col'] and row[mc['col']].strip():
                        course_code = row[mc['col']].strip().upper()
                        exams_set.add(f"{course_code}|{mc['session']}")
        
        result = []
        for e in sorted(list(exams_set)):
            code, sess = e.split('|')
            result.append({'courseCode': code, 'session': sess})
            
        return response(200, {'success': True, 'exams': result})
    except Exception as e:
        print(f"Error in handle_center_exams: {e}")
        return response(500, {'success': False, 'error': str(e)})

def handle_attendance_status(centre, course_code, session, date_str):
    try:
        s3 = boto3.client('s3')
        attendance_table = dynamodb.Table(ATTENDANCE_TABLE_NAME)

        if not all([centre, course_code, session]):
            return response(400, {'success': False, 'error': 'Missing parameters'})

        if not date_str:
            date_str = datetime.now().strftime('%d-%m-%Y')

        # 1. Load Master CSV to find registered students
        data = s3.get_object(Bucket=BUCKET_NAME, Key=BITS_EXAM_PATH)['Body'].read().decode('utf-8')
        reader = csv.reader(StringIO(data))
        headers = [h.strip() for h in next(reader)]
        
        # Find column indices based on your exact names
        def find_col(names):
            for i, h in enumerate(headers):
                if h.strip() in names or h.strip().upper() in [n.upper() for n in names]:
                    return i
            return None

        bits_id_col = find_col(['bitsId', 'BITS ID'])
        name_col = find_col(['name', 'studentName', 'NAME'])
        centre_col = find_col(['Center', 'centre', 'CENTRE'])
        exam_date_col = find_col(['examDate', 'DATE'])
        course_code_col = find_col(['courseCode', 'COURSE CODE'])
        session_col = find_col(['sessionType', 'session', 'SESSION'])

        registered_students = []
        # If we have the flat columns, use those. Otherwise fallback to the header-search
        is_flat_csv = exam_date_col is not None and course_code_col is not None

        for row in reader:
            if not row: continue
            
            # Match Center first
            if centre_col is not None and len(row) > centre_col and row[centre_col].strip().upper() == centre.strip().upper():
                
                if is_flat_csv:
                    # Flat CSV Logic: check examDate, courseCode, and sessionType columns
                    r_date = row[exam_date_col].strip() if len(row) > exam_date_col else ''
                    r_course = row[course_code_col].strip().upper() if len(row) > course_code_col else ''
                    r_session = row[session_col].strip().upper() if (session_col is not None and len(row) > session_col) else ''
                    
                    if r_date == date_str and r_course == course_code.strip().upper():
                        # If session is provided in CSV, match it too
                        if session_col is None or r_session == session.upper():
                            registered_students.append({
                                'studentId': row[bits_id_col].strip().upper() if (bits_id_col is not None and len(row) > bits_id_col) else 'UNKNOWN',
                                'studentName': row[name_col].strip() if (name_col is not None and len(row) > name_col) else 'Unknown'
                            })
                else:
                    # Fallback to the older header-search logic (just in case)
                    for i, h in enumerate(headers):
                        if date_str in h and session.upper() in h:
                            if len(row) > i and row[i].strip().upper() == course_code.strip().upper():
                                registered_students.append({
                                    'studentId': row[bits_id_col].strip().upper() if (bits_id_col is not None and len(row) > bits_id_col) else 'UNKNOWN',
                                    'studentName': row[name_col].strip() if (name_col is not None and len(row) > name_col) else 'Unknown'
                                })
                                break

        # 2. Check attendance for each registered student in DynamoDB
        # We avoid 'Scan' because the Lambda role lacks permission for it.
        # Instead, we query by bitsId (Partition Key) for each student.
        status_list = []
        completed_count = 0
        in_progress_count = 0
        
        table = dynamodb.Table(ATTENDANCE_TABLE_NAME)
        
        # Use the full course code as stored in the table (e.g. "DUMMZA111-EC3R")
        target_course = course_code.strip().upper()

        for s in registered_students:
            sid = s['studentId']
            # Convert to lowercase to match the bits-attendance-details table format (e.g. 'dummyuser1')
            sid_db = sid.strip().lower()
            status = 'Pending'
            
            try:
                # Query strictly for this student on this date/course/center
                res = table.query(
                    KeyConditionExpression=Key('bitsId').eq(sid_db),
                    FilterExpression=(
                        Attr('examDate').eq(date_str) & 
                        Attr('sessionType').eq(session.upper()) & 
                        Attr('courseCode').eq(target_course) &
                        Attr('Center').eq(centre)
                    )
                )
                items = res.get('Items', [])
                
                if items:
                    attend_record = items[0]
                    finished_time = str(attend_record.get('finished', '00:00:00'))
                    if finished_time == '00:00:00':
                        status = 'In Progress'
                        in_progress_count += 1
                    else:
                        status = 'Completed'
                        completed_count += 1
            except Exception as query_err:
                print(f"Error querying student {sid}: {query_err}")
                # Fallback to Pending if query fails
            
            status_list.append({
                'studentId': sid,
                'studentName': s['studentName'],
                'status': status
            })

        # Sort: Completed first, then In Progress, then Pending, then alphabetical
        status_sort_order = {'Completed': 0, 'In Progress': 1, 'Pending': 2}
        status_list.sort(key=lambda x: (status_sort_order.get(x['status'], 3), x['studentName']))

        return response(200, {
            'success': True,
            'total': len(registered_students),
            'present': completed_count,
            'students': status_list,
            'debug': {
                'registered_count': len(registered_students),
                'target_course': target_course,
                'target_date': date_str,
                'query_method': 'IndividualQuery'
            }
        })
    except Exception as e:
        print(f"Error in handle_attendance_status: {e}")
        return response(500, {'success': False, 'error': str(e)})
# Add this to your handle_session_history logic in lambda_function.py

def get_base_course_code(code):
    if not code:
        return ''
    return code.split('-')[0].strip().upper().replace(' ', '')

def get_center_session_registrations(centre, date_str, session):
    try:
        s3 = boto3.client('s3')
        data = s3.get_object(Bucket=BUCKET_NAME, Key=BITS_EXAM_PATH)['Body'].read().decode('utf-8')
        reader = csv.reader(StringIO(data))
        headers = [h.strip() for h in next(reader)]
        
        def find_col(names):
            for i, h in enumerate(headers):
                if h.strip() in names or h.strip().upper() in [n.upper() for n in names]:
                    return i
            return None

        bits_id_col = find_col(['bitsId', 'BITS ID'])
        centre_col = find_col(['Center', 'centre', 'CENTRE'])
        exam_date_col = find_col(['examDate', 'DATE'])
        course_code_col = find_col(['courseCode', 'COURSE CODE'])
        session_col = find_col(['sessionType', 'session', 'SESSION'])

        is_flat_csv = exam_date_col is not None and course_code_col is not None

        registered_students = set()
        active_courses = set()

        def to_dd_mm_yyyy(d):
            d = d.strip().replace('/', '-')
            if len(d) == 10 and d[4] == '-':
                try:
                    return datetime.strptime(d, '%Y-%m-%d').strftime('%d-%m-%Y')
                except:
                    pass
            return d

        target_date_dd_mm_yyyy = to_dd_mm_yyyy(date_str)
        date_pattern = re.compile(r'(\d{2}[-/]\d{2}[-/]\d{4})|(\d{4}[-/]\d{2}[-/]\d{2})')

        for row in reader:
            if not row:
                continue
            
            # Match Center
            if centre_col is not None and len(row) > centre_col and row[centre_col].strip().upper() == centre.strip().upper():
                student_id = row[bits_id_col].strip().upper() if (bits_id_col is not None and len(row) > bits_id_col) else None
                if not student_id:
                    continue

                if is_flat_csv:
                    r_date = row[exam_date_col].strip() if len(row) > exam_date_col else ''
                    r_course = row[course_code_col].strip() if len(row) > course_code_col else ''
                    r_session = row[session_col].strip().upper() if (session_col is not None and len(row) > session_col) else ''
                    
                    if to_dd_mm_yyyy(r_date) == target_date_dd_mm_yyyy:
                        if session_col is None or r_session == session.upper():
                            clean_course = get_base_course_code(r_course)
                            if clean_course:
                                registered_students.add(student_id)
                                active_courses.add(clean_course)
                else:
                    # Header-search logic using regex to locate date/session columns
                    for i, h in enumerate(headers):
                        match = date_pattern.search(h)
                        if match:
                            col_date_str = match.group(0).replace('/', '-')
                            if len(col_date_str) == 10 and col_date_str[4] == '-':  # YYYY-MM-DD
                                col_date_dd_mm = datetime.strptime(col_date_str, '%Y-%m-%d').strftime('%d-%m-%Y')
                            else:
                                col_date_dd_mm = col_date_str
                            
                            if col_date_dd_mm == target_date_dd_mm_yyyy:
                                # Find session in header
                                parts = h.upper().split('_')
                                col_session = 'FN'
                                for p in parts:
                                    p_clean = p.strip()
                                    if p_clean in ['FN', 'AN', 'EN']:
                                        col_session = p_clean
                                        break
                                
                                if col_session == session.upper():
                                    if len(row) > i and row[i].strip():
                                        clean_course = get_base_course_code(row[i])
                                        if clean_course:
                                            registered_students.add(student_id)
                                            active_courses.add(clean_course)
                                
        return registered_students, active_courses
    except Exception as e:
        print(f"Error in get_center_session_registrations: {e}")
        return set(), set()

def handle_session_history(centre, date_str=None):
    try:
        s3 = boto3.client('s3')
        if not centre:
            return response(400, {'success': False, 'error': 'Missing centre'})

        # 1. Determine Current Session from timings table
        timings = get_center_timings(centre)
        if not timings:
            return response(404, {'success': False, 'error': 'Center timings not found'})

        # 1. Handle Timezone (Assume UTC+05:30 for India)
        from datetime import timedelta
        offset = timedelta(hours=5, minutes=30)
        
        now_local = datetime.now() + offset
        current_time = now_local.strftime('%H:%M:%S')
        
        if not date_str:
            date_str = now_local.strftime('%Y-%m-%d')

        # Logic to find current or most relevant session
        session = None
        valid_sessions = []
        for s in ['FN', 'AN', 'EN']:
            start, end = get_session_times(timings, s)
            if start and end:
                valid_sessions.append({'session': s, 'start': start, 'end': end})

        if not valid_sessions:
            return response(200, {
                'success': True, 
                'session': 'None', 
                'data': [], 
                'message': 'No exam timings configured for this center.'
            })

        valid_sessions.sort(key=lambda x: x['start'])

        # Check if we are inside any session
        for vs in valid_sessions:
            if vs['start'] <= current_time <= vs['end']:
                session = vs['session']
                break

        if not session:
            # We are outside active hours. Fallback to closest session
            if current_time < valid_sessions[0]['start']:
                session = valid_sessions[0]['session']
            else:
                for vs in reversed(valid_sessions):
                    if current_time >= vs['end'] or current_time >= vs['start']:
                        session = vs['session']
                        break
                if not session:
                    session = valid_sessions[-1]['session']

        # 2. Fetch registrations for this center and session
        registered_students, active_courses = get_center_session_registrations(centre, date_str, session)

        # 3. Fetch Answer Sheets matching date, student, and course (Optimized lookup per registered student)
        results = []
        for student_id in registered_students:
            prefix = f"Exam-answers/{student_id.lower()}/{date_str}/"
            try:
                res = s3.list_objects_v2(Bucket=ANSWERS_BUCKET_NAME, Prefix=prefix)
                contents = res.get('Contents', [])
                for obj in contents:
                    key = obj['Key']
                    parts = key.split('/')
                    
                    # Path: Exam-answers/{studentId}/{date}/{courseCode}/...
                    if len(parts) >= 4:
                        course_code_clean = get_base_course_code(parts[3])
                        
                        if course_code_clean in active_courses:
                            # Convert S3 UTC time to Local Time
                            last_mod_utc = obj['LastModified']
                            last_mod_local = last_mod_utc + offset
                            upload_time = last_mod_local.strftime('%H:%M:%S')
                            
                            head = s3.head_object(Bucket=ANSWERS_BUCKET_NAME, Key=key)
                            pages = head.get('Metadata', {}).get('pages', '0')
                            
                            results.append({
                                'studentId': student_id,
                                'courseCode': parts[3],
                                'fileName': parts[-1],
                                'pageCount': pages,
                                'uploadTime': upload_time
                            })
            except Exception as s3_err:
                print(f"Error querying S3 prefix {prefix}: {s3_err}")

        return response(200, {
            'success': True, 
            'session': session, 
            'date': date_str,
            'data': results,
            'currentTime': current_time
        })
    except Exception as e:
        print(f"Error in handle_session_history: {e}")
        return response(500, {'success': False, 'error': str(e)})


# ─────────────────────────────────────────────
# S3 Upload Event Handler for finishedTable
# ─────────────────────────────────────────────
def handle_s3_upload_event(event):
    try:
        import urllib.parse
        s3 = boto3.client('s3')
        finished_table = dynamodb.Table('finishedTable')
        
        for record in event.get('Records', []):
            bucket = record['s3']['bucket']['name']
            key = urllib.parse.unquote_plus(record['s3']['object']['key'])
            
            print(f"Processing S3 Object: {bucket}/{key}")
            
            # Expected Key format: Exam-answers/{studentId}/{date}/{courseCode}/question-Q{num}.pdf
            parts = key.split('/')
            if len(parts) < 5 or parts[0] != 'Exam-answers':
                print(f"Skipping key {key} - does not match pattern")
                continue
                
            student_id = parts[1].strip().lower()
            date_str = parts[2].strip()
            course_code_raw = parts[3].strip()
            filename = parts[4].strip()
            
            # Normalize course code (e.g. "DUMMZA111-EC2B")
            course_code = course_code_raw.upper().replace(' ', '')
            
            # Convert date from yyyy-MM-dd to dd-MM-yyyy
            db_date = date_str
            if '-' in date_str:
                date_parts = date_str.split('-')
                if len(date_parts) == 3 and len(date_parts[0]) == 4:
                    db_date = f"{date_parts[2]}-{date_parts[1]}-{date_parts[0]}"
            
            # Extract question number (Q1 -> 1)
            q_match = re.search(r'Q(\d+)', filename)
            if not q_match:
                print(f"Skipping key {key} - no question number found")
                continue
            q_num = int(q_match.group(1))
            
            # Fetch page count from metadata
            head = s3.head_object(Bucket=bucket, Key=key)
            page_count = head.get('Metadata', {}).get('pages', '1')
            print(f"Found page count: {page_count} for question {q_num}")
            
            # Query attendance record to get attendanceId
            attendance_table = dynamodb.Table(ATTENDANCE_TABLE_NAME)
            filter_expr = Attr('courseCode').eq(course_code) & Attr('examDate').eq(db_date)
            res = attendance_table.query(
                KeyConditionExpression=Key('bitsId').eq(student_id),
                FilterExpression=filter_expr
            )
            items = res.get('Items', [])
            
            if not items:
                print(f"No attendance record found for {student_id} on {db_date} for course {course_code}. Skipping.")
                continue
                
            attendance_id = items[0]['attendanceId']
            
            # Update finishedTable
            question_field = f"question{q_num}"
            try:
                finished_table.update_item(
                    Key={
                        'bitsId': student_id,
                        'attendanceId': attendance_id
                    },
                    UpdateExpression=f"SET {question_field} = :page_count",
                    ExpressionAttributeValues={
                        ':page_count': str(page_count)
                    },
                    # This ensures the record already exists in finishedTable before writing
                    ConditionExpression='attribute_exists(bitsId)'
                )
                print(f"Successfully updated finishedTable for {student_id}, question {q_num} to {page_count}")
            except Exception as update_err:
                err_code = getattr(update_err, 'response', {}).get('Error', {}).get('Code', '')
                if err_code == 'ConditionalCheckFailedException':
                    print(f"Row for {student_id} and {attendance_id} does not exist in finishedTable. Skipping creation.")
                else:
                    print(f"Error updating finishedTable: {update_err}")
                
        return {'success': True, 'message': 'Processed S3 records'}
    except Exception as e:
        print(f"Unhandled error in handle_s3_upload_event: {e}")
        return {'success': False, 'error': str(e)}


