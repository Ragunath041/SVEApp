"""
AWS Lambda: bits-supervisor_app-main
Consolidated, production-grade backend service for BITS Supervisor App.

Strictly aligned with the Flutter client schemas, DynamoDB tables, and S3 paths:
1. S3 Pre-signed URL generation (Answer Sheet PDFs, Face Photos, Incident Reports, Attendance Sheets)
2. Supervisor Authentication & Profile Management (bits-Supervisor-details)
3. Exam Centre List & Centre Timings (bits-exam-centers & bits-exam-center-timings)
4. Supervisor GPS Check-in (bits-Supervisor-Attendance) & Student Exam Attendance (bits-attendance-details)
5. Finished Exam Progress Tracking (finishedTable)
6. Supervisor Duty Slots & Express Interest (bits-supervisor-requirement & bits-supervisor-requests)
7. Malpractice Incident Reporting & History (bits-supervisorapp/Incident-Reports)
8. Student Exam History (wilp-fr-model/Exam-answers)

Runtime: Python 3.11 / 3.12 (Standard AWS Lambda - zero external pip dependencies)
"""

import base64
import csv
from io import StringIO
import json
import logging
import boto3
import os
import re
from concurrent.futures import ThreadPoolExecutor
from datetime import datetime, timezone, timedelta
from decimal import Decimal
from boto3.dynamodb.conditions import Attr, Key
from botocore.config import Config

logger = logging.getLogger('bits-supervisor-app')
logger.setLevel(logging.INFO)

# ─────────────────────────────────────────────────────────────────────────────
# AWS Resource Names (Configured to match Flutter app exactly)
# ─────────────────────────────────────────────────────────────────────────────
AWS_REGION = os.environ.get('AWS_REGION', 'us-east-1')

# S3 Buckets
BUCKET_SUPERVISOR_APP = os.environ.get('BUCKET_SUPERVISOR_APP', 'bits-supervisorapp')
BUCKET_ANSWERS = os.environ.get('BUCKET_ANSWERS', 'wilp-fr-model')
BUCKET_ATTENDANCE = os.environ.get('BUCKET_ATTENDANCE', 'bits-attendance')
BUCKET_EXAM_APP = os.environ.get('BUCKET_EXAM_APP', 'bitsexamapp')
BUCKET_WILP_DATA = os.environ.get('BUCKET_WILP_DATA', 'bitswilp-data')

# DynamoDB Tables (Exact table names from Flutter Services)
TABLE_SUPERVISOR_DETAILS = os.environ.get('TABLE_SUPERVISOR_DETAILS', 'bits-Supervisor-details')
TABLE_EXAM_CENTERS = os.environ.get('TABLE_EXAM_CENTERS', 'bits-exam-centers')
TABLE_CENTER_TIMINGS = os.environ.get('TABLE_CENTER_TIMINGS', 'bits-exam-center-timings')
TABLE_SUPERVISOR_ATTENDANCE = os.environ.get('TABLE_SUPERVISOR_ATTENDANCE', 'bits-Supervisor-Attendance')
TABLE_STUDENT_ATTENDANCE = os.environ.get('TABLE_STUDENT_ATTENDANCE', 'bits-attendance-details')
TABLE_FINISHED = os.environ.get('TABLE_FINISHED', 'finishedTable')
TABLE_REQUIREMENTS = os.environ.get('TABLE_REQUIREMENTS', 'bits-supervisor-requirement')
TABLE_REQUESTS = os.environ.get('TABLE_REQUESTS', 'bits-supervisor-requests')
TABLE_SUPERVISOR_CONFIRMATION = os.environ.get('TABLE_SUPERVISOR_CONFIRMATION', 'Bits-Supervisor-Confirmation')

# S3 Client configured for SigV4 pre-signing
s3_client = boto3.client(
    's3',
    region_name=AWS_REGION,
    config=Config(signature_version='s3v4')
)

dynamodb = boto3.resource('dynamodb', region_name=AWS_REGION)

# Standard CORS Headers
HEADERS = {
    'Content-Type': 'application/json',
    'Access-Control-Allow-Origin': '*',
    'Access-Control-Allow-Methods': 'GET,POST,PUT,DELETE,OPTIONS',
    'Access-Control-Allow-Headers': 'Content-Type,X-Amz-Date,Authorization,X-Api-Key,X-Amz-Security-Token'
}


class DecimalEncoder(json.JSONEncoder):
    """Helper to serialize DynamoDB Decimal objects to JSON numbers/strings."""
    def default(self, obj):
        if isinstance(obj, Decimal):
            return int(obj) if obj % 1 == 0 else float(obj)
        return super(DecimalEncoder, self).default(obj)


def build_response(status_code, body):
    """Helper to return API Gateway / Lambda Function URL response."""
    return {
        'statusCode': status_code,
        'headers': HEADERS,
        'body': json.dumps(body, cls=DecimalEncoder)
    }


# ─────────────────────────────────────────────────────────────────────────────
# Entry Point Handler
# ─────────────────────────────────────────────────────────────────────────────
def lambda_handler(event, context):
    """Main routing handler supporting both REST paths and action payloads."""
    try:
        # Check if it is an S3 event trigger
        if 'Records' in event and event['Records'] and event['Records'][0].get('eventSource') == 'aws:s3':
            return handle_s3_upload_event(event)

        # 1. Handle CORS Preflight (OPTIONS)
        http_method = 'GET'
        if 'requestContext' in event and 'http' in event['requestContext']:
            http_method = event['requestContext']['http'].get('method', 'GET')
        elif 'httpMethod' in event:
            http_method = event.get('httpMethod', 'GET')

        if http_method == 'OPTIONS':
            return {
                'statusCode': 200,
                'headers': HEADERS,
                'body': ''
            }

        # 2. Extract Route / Action & Payload
        path = event.get('rawPath') or event.get('path') or ''
        query_params = event.get('queryStringParameters') or {}
        
        payload = {}
        body_val = event.get('body')
        
        if body_val:
            if event.get('isBase64Encoded', False) and isinstance(body_val, str):
                import base64
                body_val = base64.b64decode(body_val).decode('utf-8')
            
            if isinstance(body_val, str):
                try:
                    payload = json.loads(body_val)
                except Exception:
                    payload = {}
            elif isinstance(body_val, dict):
                payload = body_val
        elif isinstance(event, dict):
            # Direct Lambda invocation or AWS Console Test tab event
            payload = {k: v for k, v in event.items() if k not in ('requestContext', 'headers', 'multiValueHeaders')}

        # Determine action (payload > query parameters > direct event)
        raw_action = payload.get('action') or query_params.get('action') or event.get('action') or ''
        action = raw_action.strip() if isinstance(raw_action, str) else ''
        action_lower = action.lower()

        # Combined parameters for handlers
        merged_params = {**query_params, **payload}

        # 3. Router Dispatch
        # ── Health Check (Handles browser visiting root URL, /health, or empty test event) ──
        if action in ('health', 'ping') or (not action and path in ('', '/', '/health')):
            return build_response(200, {
                'success': True,
                'status': 'healthy',
                'service': 'bits-supervisor_app-main',
                'message': 'BITS Supervisor App API is live and operational.',
                'timestamp': datetime.now(timezone.utc).isoformat()
            })

        # ── S3 Pre-signed URLs ──
        if action == 'getPresignedUploadUrl' or '/uploads/presign' in path:
            return handle_presigned_upload(merged_params)
        
        if action == 'getPresignedDownloadUrl' or '/uploads/download' in path:
            return handle_presigned_download(merged_params)

        # ── Exam & Student Schedules (BITS-exam.csv & ExamDetails.csv) ──
        if action == 'centerExams' or '/exams/center-exams' in path:
            return handle_center_exams(merged_params)

        if action == 'attendanceStatus' or '/attendance/status' in path:
            return handle_attendance_status(merged_params)

        if action == 'sessionHistory' or '/exams/session-history' in path:
            return handle_session_history(merged_params)

        if action == 'saveScannedQR' or '/exams/save-scanned-qr' in path:
            return handle_save_scanned_qr(merged_params)

        if action == 'allStudents' or '/students/all' in path:
            return handle_all_student_ids()

        if action == 'studentExamDetails' or (not action and query_params.get('studentId')):
            sid = merged_params.get('studentId')
            if sid:
                return handle_student_exam_details(sid)

        if action == 'courseNameLookup' or (not action and query_params.get('courseCode')):
            return handle_course_name_lookup(merged_params)

        if action == 'studentIdsByDate' or (not action and query_params.get('date')):
            return handle_student_ids_by_date(merged_params)

        # ── Supervisor Authentication & Centres ──
        if action_lower in ('getsupervisordetails', 'get_supervisor_details', 'supervisordetails') or '/auth/supervisor-details' in path or '/supervisor/details' in path:
            return handle_get_supervisor_details(merged_params)

        if action_lower in ('login', 'validatesupervisor', 'validate_supervisor') or '/auth/login' in path:
            return handle_supervisor_login(merged_params)

        if action == 'getCentres' or '/auth/centres' in path:
            return handle_get_centres()

        if action == 'getCenterTimings' or '/auth/timings' in path:
            return handle_get_center_timings(merged_params)

        if action == 'registerSupervisor' or action == 'updateSupervisor' or '/auth/register' in path:
            return handle_register_or_update_supervisor(merged_params)

        # ── Attendance ──
        if action == 'supervisorCheckIn' or action == 'markAttendance' or '/attendance/supervisor-checkin' in path:
            return handle_supervisor_checkin(merged_params)

        if action == 'saveStudentAttendance' or '/attendance/student-record' in path:
            return handle_save_student_attendance(merged_params)

        if action == 'updateFinishedTime' or '/attendance/update-finished' in path:
            return handle_update_finished_time(merged_params)

        if action == 'decrementQuestionsPending' or '/attendance/decrement-questions' in path:
            return handle_decrement_questions(merged_params)

        if action == 'getExistingAttendance' or '/attendance/existing' in path:
            return handle_get_existing_attendance(merged_params)

        if action == 'markIncidentAttendance' or action == 'markIncident' or '/attendance/mark-incident' in path:
            return handle_mark_incident_attendance(merged_params)

        # ── Finished Exam Progress Table ──
        if action == 'initFinishedRecord' or '/finished/init' in path:
            return handle_init_finished_record(merged_params)

        if action == 'updateFinishedQuestion' or '/finished/update-question' in path:
            return handle_update_finished_question(merged_params)

        # ── Duty Requirements & Slots ──
        if action == 'getRequirements' or action == 'fetchRequirements' or '/requirements/list' in path:
            return handle_get_requirements(merged_params)

        if action == 'expressInterest' or action == 'submitInterestRequests' or '/requirements/express-interest' in path:
            return handle_express_interest(merged_params)

        # ── Incident Reports ──
        if action == 'saveIncident' or '/incidents/save' in path:
            return handle_save_incident(merged_params)

        if action == 'getIncidentHistory' or action == 'fetchIncidentHistory' or '/incidents/history' in path:
            return handle_get_incident_history(merged_params)

        # ── Student Exam History ──
        if action == 'getStudentExamHistory' or '/exams/history' in path:
            return handle_get_student_exam_history(merged_params)

        if action == 'batchCheckCompletedAnswers' or '/exams/batch-check-answers' in path:
            return handle_batch_check_completed_answers(merged_params)

        # ── Question Slots ──
        if action == 'getQuestionSlots' or '/exams/question-slots' in path:
            return handle_get_question_slots(merged_params)

        # ── Tabswitch Violations ──
        if action == 'getTabSwitchViolations' or '/violations/list' in path:
            return handle_get_tabswitch_violations(merged_params)

        if action == 'countViolations' or '/violations/count' in path:
            return handle_count_violations(merged_params)

        return build_response(400, {
            'success': False,
            'error': f'Unsupported action: "{action}" or path: "{path}".'
        })

    except Exception as e:
        print(f"Unhandled exception in lambda_handler: {e}")
        return build_response(500, {
            'success': False,
            'error': f'Internal Server Error: {str(e)}'
        })


# ─────────────────────────────────────────────────────────────────────────────
# 1. S3 Pre-Signed URL Handlers
# ─────────────────────────────────────────────────────────────────────────────
def handle_presigned_upload(params):
    """
    Generates a secure S3 PUT pre-signed URL.
    
    Supported upload types:
      - 'answer_sheet': wilp-fr-model/Exam-answers/{studentId}/{date}/{courseCode}/question-{slot}.pdf
      - 'supervisor_face': bits-supervisorapp/Supervisor-details/{supervisorId}/{suffix}
      - 'registration_json': bits-supervisorapp/Supervisor-details/{supervisorId}/registration.json
      - 'incident_photo': bits-supervisorapp/Incident-Reports/{supervisorId}/{date}/{studentId}_photos/{fileName}
      - 'incident_pdf': bits-supervisorapp/Incident-Reports/{supervisorId}/{date}/{studentId}_report.pdf
      - 'incident_json': bits-supervisorapp/Incident-Reports/{supervisorId}/{date}/{studentId}_incident.json
      - 'attendance_sheet': bits-attendance/{date}_{session}_{centre}/{fileName}
    """
    upload_type = params.get('uploadType', '')
    meta = params.get('metadata') or params  # Supports both nested and flat parameters
    content_type = params.get('contentType', 'application/octet-stream')
    expires_in = int(params.get('expiresIn', 900))  # 15 minutes

    bucket = BUCKET_SUPERVISOR_APP
    key = ''

    if upload_type == 'answer_sheet':
        bucket = BUCKET_ANSWERS
        student_id = str(meta.get('studentId', '')).strip().lower()
        exam_date = str(meta.get('date', '')).strip()
        course_code = str(meta.get('courseCode', '')).strip().upper()
        slot = str(meta.get('slot', 'Q1')).strip().upper()
        if not slot.startswith('Q'):
            slot = f"Q{slot}"

        if not all([student_id, exam_date, course_code]):
            return build_response(400, {'success': False, 'error': 'Missing studentId, date, or courseCode'})

        # Format: Exam-answers/{studentId}/{date}/{courseCode}/question-{slot}.pdf
        key = f"Exam-answers/{student_id}/{exam_date}/{course_code}/question-{slot}.pdf"
        content_type = 'application/pdf'

    elif upload_type == 'supervisor_face':
        bucket = BUCKET_SUPERVISOR_APP
        supervisor_id = str(meta.get('supervisorId', '')).strip()
        suffix = str(meta.get('suffix', 'face.jpg')).strip()
        if not supervisor_id:
            return build_response(400, {'success': False, 'error': 'Missing supervisorId'})
        key = f"Supervisor-details/{supervisor_id}/{suffix}"
        content_type = 'image/jpeg'

    elif upload_type == 'registration_json':
        bucket = BUCKET_SUPERVISOR_APP
        supervisor_id = str(meta.get('supervisorId', '')).strip()
        if not supervisor_id:
            return build_response(400, {'success': False, 'error': 'Missing supervisorId'})
        key = f"Supervisor-details/{supervisor_id}/registration.json"
        content_type = 'application/json'

    elif upload_type == 'incident_photo':
        bucket = BUCKET_SUPERVISOR_APP
        supervisor_id = str(meta.get('supervisorId', '')).strip()
        date_str = str(meta.get('date', '')).strip()
        student_id = str(meta.get('studentId', 'unknown')).strip()
        file_name = str(meta.get('fileName', 'photo_1.jpg')).strip()
        key = f"Incident-Reports/{supervisor_id}/{date_str}/{student_id}_photos/{file_name}"
        content_type = 'image/jpeg'

    elif upload_type == 'incident_pdf':
        bucket = BUCKET_SUPERVISOR_APP
        supervisor_id = str(meta.get('supervisorId', '')).strip()
        date_str = str(meta.get('date', '')).strip()
        student_id = str(meta.get('studentId', 'unknown')).strip()
        key = f"Incident-Reports/{supervisor_id}/{date_str}/{student_id}_report.pdf"
        content_type = 'application/pdf'

    elif upload_type == 'incident_json':
        bucket = BUCKET_SUPERVISOR_APP
        supervisor_id = str(meta.get('supervisorId', '')).strip()
        date_str = str(meta.get('date', '')).strip()
        student_id = str(meta.get('studentId', 'unknown')).strip()
        key = f"Incident-Reports/{supervisor_id}/{date_str}/{student_id}_incident.json"
        content_type = 'application/json'

    elif upload_type == 'attendance_sheet':
        bucket = BUCKET_ATTENDANCE
        date_str = str(meta.get('date', '')).strip()
        session = str(meta.get('session', '')).strip()
        centre = str(meta.get('centre', '')).strip()
        file_name = str(meta.get('fileName', 'attendancesheet_1.png')).strip()
        key = f"{date_str}_{session}_{centre}/{file_name}"
        content_type = 'image/png'

    elif upload_type in ('custom', 'direct', '') or params.get('key') or meta.get('key'):
        key = str(params.get('key') or meta.get('key', '')).strip()
        bucket = str(params.get('bucket') or meta.get('bucket', '') or BUCKET_SUPERVISOR_APP).strip()
        content_type = params.get('contentType') or meta.get('contentType') or content_type
        if not key:
            return build_response(400, {'success': False, 'error': 'Missing S3 key'})

    else:
        return build_response(400, {'success': False, 'error': f"Unknown uploadType: '{upload_type}'"})

    # Optional custom S3 object metadata (e.g. {'pages': '2'})
    custom_metadata = meta.get('s3Metadata') or {}

    put_params = {
        'Bucket': bucket,
        'Key': key,
        'ContentType': content_type
    }
    if custom_metadata:
        put_params['Metadata'] = {k.lower(): str(v).strip() for k, v in custom_metadata.items()}

    presigned_url = s3_client.generate_presigned_url(
        ClientMethod='put_object',
        Params=put_params,
        ExpiresIn=expires_in
    )

    return build_response(200, {
        'success': True,
        'uploadUrl': presigned_url,
        'bucket': bucket,
        'key': key,
        'contentType': content_type,
        'expiresIn': expires_in
    })


def handle_presigned_download(params):
    """Generates a temporary S3 GET pre-signed URL to safely view private files."""
    bucket = params.get('bucket', BUCKET_ANSWERS)
    key = params.get('key', '').strip()
    expires_in = int(params.get('expiresIn', 900))

    if not key:
        return build_response(400, {'success': False, 'error': 'Missing key'})

    presigned_url = s3_client.generate_presigned_url(
        ClientMethod='get_object',
        Params={'Bucket': bucket, 'Key': key},
        ExpiresIn=expires_in
    )

    return build_response(200, {
        'success': True,
        'downloadUrl': presigned_url,
        'expiresIn': expires_in
    })


# ─────────────────────────────────────────────────────────────────────────────
# 2. Supervisor Authentication, Profile & Centre Handlers
# ─────────────────────────────────────────────────────────────────────────────
def handle_supervisor_login(payload):
    """
    Validates supervisor credentials against bits-Supervisor-details.
    Matches exact keys and schema from DynamoDBExtraction.validateSupervisor()
    """
    supervisor_id = payload.get('supervisorId', '').strip()
    centre = payload.get('centre', '').strip()
    invigilator_type = payload.get('invigilatorType', '').strip()

    if not supervisor_id:
        return build_response(400, {'success': False, 'error': 'Supervisor ID is required.'})

    table = dynamodb.Table(TABLE_SUPERVISOR_DETAILS)
    res = table.get_item(Key={'Supervisor_id': supervisor_id})
    item = res.get('Item')

    if not item:
        return build_response(404, {
            'success': False,
            'error': 'Supervisor ID not found.',
            'errorType': 'supervisor_id'
        })

    # Exact column names in bits-Supervisor-details
    db_centre = (item.get('Exam hall') or item.get('centre') or item.get('center') or '').strip()
    db_type = (item.get('Type') or item.get('type') or item.get('invigilator_type') or '').strip()
    db_name = (item.get('Name') or item.get('name') or item.get('full_name') or item.get('FullName') or '').strip()
    db_email = item.get('Email', '').strip()
    db_phone = item.get('PhoneNumber') or item.get('Phone') or item.get('phone') or ''
    db_city = item.get('City', '').strip()
    db_address = item.get('Address', '').strip()

    common_data = {
        'supervisor_id': supervisor_id,
        'name': db_name,
        'full_name': db_name,
        'centre': db_centre,
        'Exam hall': db_centre,
        'type': db_type,
        'invigilator_type': db_type,
        'email': db_email,
        'phone': str(db_phone),
        'phoneNumber': str(db_phone),
        'city': db_city,
        'address': db_address
    }

    if centre and db_centre.lower() != centre.lower():
        return build_response(400, {
            'success': False,
            'error': 'Location Mismatch.',
            'errorType': 'centre',
            'expected': db_centre,
            'provided': centre,
            'data': common_data
        })

    if invigilator_type and db_type.lower() != invigilator_type.lower():
        return build_response(400, {
            'success': False,
            'error': 'Mismatch Designation.',
            'errorType': 'invigilator_type',
            'expected': db_type,
            'provided': invigilator_type,
            'data': common_data
        })

    return build_response(200, {
        'success': True,
        'message': 'Validation successful.',
        'data': common_data
    })


def handle_get_supervisor_details(payload):
    """
    Fetches supervisor details directly by Supervisor ID from bits-Supervisor-details.
    Does not enforce centre or invigilator designation matching.
    Returns supervisor name, centre, type, phone, email, city, and address.
    """
    supervisor_id = (payload.get('supervisorId') or payload.get('supervisor_id') or '').strip()

    if not supervisor_id:
        return build_response(400, {'success': False, 'error': 'Supervisor ID is required.'})

    table = dynamodb.Table(TABLE_SUPERVISOR_DETAILS)
    item = None

    # 1. Primary lookup using exact schema 'Supervisor_id' (String)
    try:
        res = table.get_item(Key={'Supervisor_id': supervisor_id})
        item = res.get('Item')
    except Exception as e:
        logger.warning(f"get_item with 'Supervisor_id' (string) failed: {e}")

    # Fallback to int if supervisor_id is numeric
    if not item and supervisor_id.isdigit():
        try:
            res = table.get_item(Key={'Supervisor_id': int(supervisor_id)})
            item = res.get('Item')
        except Exception:
            pass

    # 2. Fallback to lowercase 'supervisor_id' key
    if not item:
        try:
            res = table.get_item(Key={'supervisor_id': supervisor_id})
            item = res.get('Item')
        except Exception:
            pass
        if not item and supervisor_id.isdigit():
            try:
                res = table.get_item(Key={'supervisor_id': int(supervisor_id)})
                item = res.get('Item')
            except Exception:
                pass

    # 3. Fallback scan if key casing differs
    if not item:
        try:
            cond = Attr('Supervisor_id').eq(supervisor_id) | Attr('supervisor_id').eq(supervisor_id)
            if supervisor_id.isdigit():
                cond = cond | Attr('Supervisor_id').eq(int(supervisor_id)) | Attr('supervisor_id').eq(int(supervisor_id))
            scan_res = table.scan(FilterExpression=cond)
            items = scan_res.get('Items', [])
            if items:
                item = items[0]
        except Exception as e:
            logger.warning(f"Scan fallback error: {e}")

    if not item:
        return build_response(404, {
            'success': False,
            'error': f'Supervisor ID "{supervisor_id}" not found in {TABLE_SUPERVISOR_DETAILS}.',
            'errorType': 'supervisor_id'
        })

    # Exact column names in bits-Supervisor-details with comprehensive fallbacks
    name = (item.get('Name') or item.get('name') or item.get('full_name') or item.get('FullName') or '').strip()
    centre = (item.get('Exam hall') or item.get('centre') or item.get('center') or item.get('ExamHall') or '').strip()
    invigilator_type = (item.get('Type') or item.get('type') or item.get('invigilator_type') or item.get('Designation') or '').strip()
    email = (item.get('Email') or item.get('email') or '').strip()
    phone = (item.get('PhoneNumber') or item.get('phone') or item.get('Phone') or item.get('phone_number') or '')
    city = (item.get('City') or item.get('city') or '').strip()
    address = (item.get('Address') or item.get('address') or '').strip()

    data = {
        'supervisor_id': supervisor_id,
        'name': name,
        'full_name': name,
        'centre': centre,
        'Exam hall': centre,
        'type': invigilator_type,
        'invigilator_type': invigilator_type,
        'email': email,
        'phone': str(phone).strip(),
        'phoneNumber': str(phone).strip(),
        'city': city,
        'address': address
    }

    return build_response(200, {
        'success': True,
        'message': 'Supervisor details retrieved successfully.',
        'data': data
    })


def handle_get_centres():
    """
    Returns list of exam halls from bits-exam-centers table.
    Matches schema from DynamoDBExtraction.dart and AttendanceService.dart
    """
    table = dynamodb.Table(TABLE_EXAM_CENTERS)
    res = table.scan()
    items = res.get('Items', [])
    centres = []

    for item in items:
        centre_name = item.get('exam-hall') or item.get('centre') or item.get('center')
        if centre_name:
            centres.append({
                'name': centre_name,
                'city': item.get('city', ''),
                'maxLatitude': str(item.get('maxLatitude', '')),
                'minLatitude': str(item.get('minLatitude', '')),
                'maxLongitude': str(item.get('maxLongitude', '')),
                'minLongitude': str(item.get('minLongitude', ''))
            })

    centres.sort(key=lambda x: x['name'])
    return build_response(200, {'success': True, 'centres': centres})


def handle_get_center_timings(params):
    """
    Returns session timings (FN, AN, EN) for a given centre.
    Reads from bits-exam-center-timings (matches DynamoDBExtraction.getCenterTimings)
    """
    centre_name = params.get('centre') or params.get('centreName') or ''
    centre_name = str(centre_name).strip()

    if not centre_name:
        return build_response(400, {'success': False, 'error': 'Missing centre'})

    table = dynamodb.Table(TABLE_CENTER_TIMINGS)
    res = table.get_item(Key={'exam-hall': centre_name})
    item = res.get('Item')

    if not item:
        # Fallback scan if key casing differs
        scan_res = table.scan(FilterExpression=Attr('exam-hall').eq(centre_name))
        items = scan_res.get('Items', [])
        if items:
            item = items[0]

    if not item:
        return build_response(404, {'success': False, 'error': f'No timings configured for {centre_name}'})

    timings = {
        'FN_start': item.get('FN_start') or item.get('FN Start') or '',
        'FN_end': item.get('FN_end') or item.get('FN End') or '',
        'AN_start': item.get('AN_start') or item.get('AN Start') or '',
        'AN_end': item.get('AN_end') or item.get('AN End') or '',
        'EN_start': item.get('EN_start') or item.get('EN Start') or '',
        'EN_end': item.get('EN_end') or item.get('EN End') or ''
    }

    return build_response(200, {'success': True, 'timings': timings, 'centre': centre_name})


def handle_register_or_update_supervisor(payload):
    """
    Saves or updates supervisor profile in bits-Supervisor-details.
    Matches exact DynamoDB schema used in DynamoDBExtraction.updateSupervisor()
    """
    supervisor_id = payload.get('supervisorId', '').strip()
    if not supervisor_id:
        return build_response(400, {'success': False, 'error': 'Missing supervisorId'})

    table = dynamodb.Table(TABLE_SUPERVISOR_DETAILS)

    item = {
        'Supervisor_id': supervisor_id,
        'Exam hall': payload.get('centre', '').strip(),
        'Type': payload.get('invigilatorType', '').strip(),
        'PhoneNumber': str(payload.get('phoneNumber') or payload.get('phone', '')).strip(),
        'City': payload.get('city', '').strip(),
        'Address': payload.get('address', '').strip(),
        'RegisteredAt': datetime.now(timezone.utc).isoformat()
    }

    if payload.get('fullName') or payload.get('name'):
        item['Name'] = str(payload.get('fullName') or payload.get('name')).strip()
    if payload.get('email'):
        item['Email'] = str(payload.get('email')).strip()

    table.put_item(Item=item)
    return build_response(200, {'success': True, 'message': 'Supervisor details saved successfully'})


# ─────────────────────────────────────────────────────────────────────────────
# 3. Attendance Handlers
# ─────────────────────────────────────────────────────────────────────────────
def handle_supervisor_checkin(payload):
    """
    Records supervisor GPS attendance in bits-Supervisor-Attendance.
    Matches exact schema from AttendanceService.markAttendance():
      - Partition Key: 'supervisor-id'
      - Sort Key: 'timestamp'
    """
    supervisor_id = payload.get('supervisorId', '').strip()
    centre = payload.get('centre', '').strip()
    name = payload.get('name', '').strip()
    email = payload.get('email', '').strip()
    invigilator_type = payload.get('invigilatorType', '').strip()
    lat = payload.get('latitude', 0.0)
    lng = payload.get('longitude', 0.0)

    if not supervisor_id or not centre:
        return build_response(400, {'success': False, 'error': 'Missing supervisorId or centre'})

    # Prefer mobile device local time, date, and timestamp from payload
    client_date = payload.get('date') or payload.get('loginDate')
    client_time = payload.get('time') or payload.get('loginTime')
    client_timestamp = payload.get('timestamp')

    now = datetime.now()
    date_str = str(client_date).strip() if client_date else now.strftime('%Y-%m-%d')
    time_str = str(client_time).strip() if client_time else now.strftime('%H:%M:%S')
    timestamp_val = str(client_timestamp).strip() if client_timestamp else f"{date_str}T{time_str}"

    table = dynamodb.Table(TABLE_SUPERVISOR_ATTENDANCE)

    item = {
        'supervisor-id': supervisor_id,
        'timestamp': timestamp_val,
        'name': name,
        'email': email,
        'invigilator_type': invigilator_type,
        'centre': centre,
        'date': date_str,
        'time': time_str,
        'latitude': Decimal(str(lat)),
        'longitude': Decimal(str(lng))
    }

    table.put_item(Item=item)
    return build_response(200, {
        'success': True,
        'message': 'Attendance marked successfully.',
        'data': {
            'supervisor_id': supervisor_id,
            'timestamp': timestamp_val,
            'centre': centre
        }
    })


def handle_save_student_attendance(payload):
    """
    Saves student exam attendance in bits-attendance-details.
    Matches exact schema from DynamoDBAttendanceService.saveLoginRecord():
      - Partition Key: 'bitsId'
      - Sort Key: 'attendanceId'
    """
    bits_id = str(payload.get('bitsId', '')).strip().lower()
    course_code = str(payload.get('courseCode', '')).strip().upper().replace(' ', '')
    exam_date = str(payload.get('examDate', '')).strip()
    center = str(payload.get('center') or payload.get('centre', '')).strip()

    if not all([bits_id, course_code, exam_date, center]):
        return build_response(400, {'success': False, 'error': 'Missing required student attendance fields'})

    now = datetime.now(timezone.utc)
    epoch_ms = int(now.timestamp() * 1000)
    attendance_id = payload.get('attendanceId') or f"{bits_id}_{epoch_ms}"

    lat = Decimal(str(payload.get('latitude', 0.0)))
    lng = Decimal(str(payload.get('longitude', 0.0)))

    table = dynamodb.Table(TABLE_STUDENT_ATTENDANCE)

    item = {
        'bitsId': bits_id,
        'attendanceId': attendance_id,
        'loginDate': payload.get('loginDate') or now.strftime('%Y-%m-%d'),
        'loginTime': payload.get('loginTime') or now.strftime('%H:%M:%S'),
        'latitude': lat,
        'longitude': lng,
        'timestamp': epoch_ms,
        'finished': payload.get('finished', '00:00:00'),
        'noOfQuestionsPending': int(payload.get('noOfQuestionsPending', 0)),
        'courseCode': course_code,
        'examDate': exam_date,
        'examStartTime': payload.get('examStartTime', ''),
        'examEndTime': payload.get('examEndTime', ''),
        'sessionType': str(payload.get('sessionType', 'FN')).strip().upper(),
        'Center': center,
        'uploadStartTime': payload.get('uploadStartTime') or now.strftime('%H:%M:%S')
    }

    table.put_item(Item=item)
    return build_response(200, {
        'success': True,
        'message': 'Student attendance saved successfully',
        'attendanceId': attendance_id
    })


def handle_mark_incident_attendance(payload):
    """
    Marks student attendance finished column as '99:99:99' when malpractice occurs.
    Matches DynamoDBAttendanceService.markAsIncident()
    """
    student_id = str(payload.get('bitsId') or payload.get('studentId', '')).strip().lower()
    course_code = str(payload.get('courseCode', '')).strip().upper().replace(' ', '')
    exam_date = str(payload.get('examDate', '')).strip()
    session = payload.get('session')

    if not all([student_id, course_code, exam_date]):
        return build_response(400, {'success': False, 'error': 'Missing bitsId, courseCode, or examDate'})

    table = dynamodb.Table(TABLE_STUDENT_ATTENDANCE)

    filter_expr = Attr('courseCode').eq(course_code) & Attr('examDate').eq(exam_date)
    if session:
        filter_expr = filter_expr & Attr('sessionType').eq(session.strip().upper())

    res = table.query(
        KeyConditionExpression=Key('bitsId').eq(student_id),
        FilterExpression=filter_expr
    )
    items = res.get('Items', [])

    if not items:
        return build_response(404, {'success': False, 'error': 'Attendance record not found for incident mark'})

    attendance_id = items[0]['attendanceId']
    table.update_item(
        Key={'bitsId': student_id, 'attendanceId': attendance_id},
        UpdateExpression='SET finished = :code',
        ExpressionAttributeValues={':code': '99:99:99'}
    )

    return build_response(200, {'success': True, 'message': 'Student attendance marked as incident (99:99:99)'})


def handle_update_finished_time(payload):
    """Updates finished column in bits-attendance-details when student completes exam."""
    bits_id = str(payload.get('bitsId', '')).strip().lower()
    attendance_id = str(payload.get('attendanceId', '')).strip()
    finished_time = str(payload.get('finishedTime', '')).strip()

    if not all([bits_id, attendance_id, finished_time]):
        return build_response(400, {'success': False, 'error': 'Missing bitsId, attendanceId, or finishedTime'})

    table = dynamodb.Table(TABLE_STUDENT_ATTENDANCE)
    table.update_item(
        Key={'bitsId': bits_id, 'attendanceId': attendance_id},
        UpdateExpression='SET finished = :finishedTime',
        ExpressionAttributeValues={':finishedTime': finished_time}
    )
    return build_response(200, {'success': True, 'message': 'Finished time updated'})


def handle_decrement_questions(payload):
    """Decrements noOfQuestionsPending by 1 when a question is uploaded."""
    bits_id = str(payload.get('bitsId', '')).strip().lower()
    attendance_id = str(payload.get('attendanceId', '')).strip()

    if not all([bits_id, attendance_id]):
        return build_response(400, {'success': False, 'error': 'Missing bitsId or attendanceId'})

    table = dynamodb.Table(TABLE_STUDENT_ATTENDANCE)
    try:
        table.update_item(
            Key={'bitsId': bits_id, 'attendanceId': attendance_id},
            UpdateExpression='SET noOfQuestionsPending = noOfQuestionsPending - :dec',
            ConditionExpression='noOfQuestionsPending > :zero',
            ExpressionAttributeValues={':dec': 1, ':zero': 0}
        )
        return build_response(200, {'success': True, 'message': 'Questions pending decremented'})
    except Exception as e:
        # Ignore conditional check failed (already 0)
        return build_response(200, {'success': True, 'message': 'Questions pending at minimum'})


def handle_get_existing_attendance(payload):
    """Queries bits-attendance-details to see if attendance already exists for session."""
    bits_id = str(payload.get('bitsId', '')).strip().lower()
    course_code = str(payload.get('courseCode', '')).strip().upper().replace(' ', '')
    exam_date = str(payload.get('examDate', '')).strip()
    session_type = payload.get('sessionType')

    if not all([bits_id, course_code, exam_date]):
        return build_response(400, {'success': False, 'error': 'Missing bitsId, courseCode, or examDate'})

    table = dynamodb.Table(TABLE_STUDENT_ATTENDANCE)
    filter_expr = Attr('courseCode').eq(course_code) & Attr('examDate').eq(exam_date)
    if session_type:
        filter_expr = filter_expr & Attr('sessionType').eq(session_type.strip().upper())

    res = table.query(
        KeyConditionExpression=Key('bitsId').eq(bits_id),
        FilterExpression=filter_expr
    )
    items = res.get('Items', [])
    if items:
        return build_response(200, {'success': True, 'attendanceId': items[0]['attendanceId'], 'data': items[0]})
    return build_response(200, {'success': True, 'attendanceId': None})


# ─────────────────────────────────────────────────────────────────────────────
# 4. Finished Table (Progress Tracking for 15 Questions)
# ─────────────────────────────────────────────────────────────────────────────
def handle_init_finished_record(payload):
    """
    Initializes finishedTable record with all questions set to "0" without overwriting existing questions.
    Matches DynamoDBFinishedService.createInitialRecord():
      - Partition Key: 'bitsId'
      - Sort Key: 'attendanceId'
    """
    bits_id = str(payload.get('bitsId', '')).strip().lower()
    attendance_id = str(payload.get('attendanceId', '')).strip()
    course_code = str(payload.get('courseCode', '')).strip().upper().replace(' ', '')
    exam_date = str(payload.get('examDate', '')).strip()
    session_type = str(payload.get('sessionType', 'FN')).strip().upper()

    if not all([bits_id, attendance_id]):
        return build_response(400, {'success': False, 'error': 'Missing bitsId or attendanceId'})

    table = dynamodb.Table(TABLE_FINISHED)
    created_at = datetime.now(timezone.utc).isoformat()

    update_expr = (
        'SET courseCode = :courseCode, '
        'examDate = :examDate, '
        'sessionType = :sessionType, '
        'createdAt = :createdAt, '
        + ', '.join([f'question{i} = if_not_exists(question{i}, :zero)' for i in range(1, 16)])
    )

    expr_values = {
        ':courseCode': course_code,
        ':examDate': exam_date,
        ':sessionType': session_type,
        ':createdAt': created_at,
        ':zero': '0'
    }

    table.update_item(
        Key={'bitsId': bits_id, 'attendanceId': attendance_id},
        UpdateExpression=update_expr,
        ExpressionAttributeValues=expr_values
    )

    return build_response(200, {'success': True, 'message': 'Initialized finishedTable record'})


def handle_update_finished_question(payload):
    """Updates a specific question column (e.g. question1..question15) in finishedTable."""
    bits_id = str(payload.get('bitsId', '')).strip().lower()
    attendance_id = str(payload.get('attendanceId', '')).strip()
    question_num = int(payload.get('questionNumber', 0))
    val = str(payload.get('value', '')).strip()

    if not all([bits_id, attendance_id]) or question_num < 1 or question_num > 15:
        return build_response(400, {'success': False, 'error': 'Invalid parameters'})

    table = dynamodb.Table(TABLE_FINISHED)
    q_col = f"question{question_num}"
    table.update_item(
        Key={'bitsId': bits_id, 'attendanceId': attendance_id},
        UpdateExpression=f'SET {q_col} = :val',
        ExpressionAttributeValues={':val': val}
    )
    return build_response(200, {'success': True, 'message': f'{q_col} updated'})


# ─────────────────────────────────────────────────────────────────────────────
# 5. Duty Requirements & Slot Requests Handlers
# ─────────────────────────────────────────────────────────────────────────────
def handle_get_requirements(params):
    """
    Queries supervisor requirements from bits-supervisor-requirement and calculates booked slots.
    Matches exact logic from SupervisorRequirementService.fetchRequirements():
      - Parses 'No_FN_Supervisors', 'No_AN_Supervisors', 'No_EN_Supervisors'
      - Counts matching requests in bits-supervisor-requests (ReqId_Session)
    """
    city_filter = params.get('city', '').strip()
    supervisor_id = params.get('supervisorId', '').strip().lower()

    req_table = dynamodb.Table(TABLE_REQUIREMENTS)
    req_res = req_table.scan()
    raw_slots = req_res.get('Items', [])

    # Get request counts from bits-supervisor-requests
    requests_table = dynamodb.Table(TABLE_REQUESTS)
    requests_res = requests_table.scan()
    request_items = requests_res.get('Items', [])

    slot_counts = {}
    my_requested_slots = set()

    for r in request_items:
        r_id = str(r.get('ReqId') or r.get('reqId') or '').strip()
        session = str(r.get('Session') or r.get('session') or '').strip()
        sup_val = str(r.get('Supervisor') or r.get('supervisorId') or '').strip().lower()

        if r_id and session:
            key = f"{r_id}_{session}"
            slot_counts[key] = slot_counts.get(key, 0) + 1

            if supervisor_id and sup_val == supervisor_id:
                my_requested_slots.add(key)

    formatted_slots = []
    session_columns = ['No_FN_Supervisors', 'No_AN_Supervisors', 'No_EN_Supervisors']

    for item in raw_slots:
        city = (item.get('City') or item.get('city') or '').strip()
        center = (item.get('Center') or item.get('center') or item.get('centre') or '').strip()
        date = (item.get('Date') or item.get('date') or '').strip()
        req_id = str(item.get('ReqId') or item.get('reqId') or '').strip()

        if not city or not center or not date:
            continue

        if city_filter and city.lower() != city_filter.lower():
            continue

        for col in session_columns:
            raw_val = item.get(col, 0)
            required_count = int(raw_val) if raw_val is not None else 0

            if required_count > 0:
                session_tag = col.replace('No_', '').replace('_Supervisors', '')
                slot_key = f"{req_id}_{session_tag}"
                current_requests = slot_counts.get(slot_key, 0)
                is_submitted = slot_key in my_requested_slots
                is_full = current_requests >= required_count

                formatted_slots.append({
                    'reqId': req_id,
                    'city': city,
                    'center': center,
                    'date': date,
                    'session': session_tag,
                    'requiredCount': required_count,
                    'currentRequestCount': current_requests,
                    'isSubmitted': is_submitted,
                    'isFull': is_full
                })

    # Sort slots by city, then date, then center, then session
    formatted_slots.sort(key=lambda x: (x['city'], x['date'], x['center'], x['session']))

    return build_response(200, {'success': True, 'slots': formatted_slots})


def handle_express_interest(payload):
    """
    Submits supervisor interest to bits-supervisor-requests.
    Matches exact schema from SupervisorRequirementService.submitInterestRequests():
      - ReqId: Number
      - DateTime: ISO8601 String
      - Session: String (FN, AN, EN)
      - Supervisor: String (supervisor ID)
    """
    supervisor_id = payload.get('supervisorId', '').strip()
    slots = payload.get('slots') or []

    # If single slot payload passed
    if not slots and payload.get('reqId'):
        slots = [{
            'reqId': payload.get('reqId'),
            'session': payload.get('session')
        }]

    if not supervisor_id or not slots:
        return build_response(400, {'success': False, 'error': 'Missing supervisorId or slots'})

    table = dynamodb.Table(TABLE_REQUESTS)
    now = datetime.now(timezone.utc)

    for i, slot in enumerate(slots):
        req_id_raw = str(slot.get('reqId', '0')).strip()
        req_id_num = int(req_id_raw) if req_id_raw.isdigit() else 0
        session = str(slot.get('session', 'FN')).strip()
        timestamp_str = now.isoformat()

        item = {
            'ReqId': req_id_num,
            'DateTime': timestamp_str,
            'Session': session,
            'Supervisor': supervisor_id
        }
        table.put_item(Item=item)

    return build_response(200, {'success': True, 'message': 'Interest submitted successfully'})


# ─────────────────────────────────────────────────────────────────────────────
# 6. Incident Reporting & History Handlers
# ─────────────────────────────────────────────────────────────────────────────
def handle_save_incident(payload):
    """
    Saves incident report metadata to S3 bits-supervisorapp/Incident-Reports.
    Matches StorageService.uploadIncidentReport()
    """
    supervisor_id = str(payload.get('supervisorId', '')).strip()
    student_id = str(payload.get('studentId', 'unknown')).strip()
    now = datetime.now(timezone.utc)
    date_str = payload.get('date') or now.strftime('%Y-%m-%d')

    if not supervisor_id or not student_id:
        return build_response(400, {'success': False, 'error': 'Missing supervisorId or studentId'})

    json_key = f"Incident-Reports/{supervisor_id}/{date_str}/{student_id}_incident.json"

    # Save to S3
    s3_client.put_object(
        Bucket=BUCKET_SUPERVISOR_APP,
        Key=json_key,
        Body=json.dumps(payload, cls=DecimalEncoder),
        ContentType='application/json'
    )

    return build_response(200, {
        'success': True,
        'message': 'Incident report saved successfully',
        'key': json_key
    })


def handle_get_incident_history(params):
    """
    Lists past incidents for a supervisor with temporary pre-signed view URLs for photos and PDFs.
    Matches S3IncidentService.fetchIncidentHistory()
    """
    supervisor_id = str(params.get('supervisorId', '')).strip()
    if not supervisor_id:
        return build_response(400, {'success': False, 'error': 'Missing supervisorId'})

    prefix = f"Incident-Reports/{supervisor_id}/"
    res = s3_client.list_objects_v2(Bucket=BUCKET_SUPERVISOR_APP, Prefix=prefix)
    contents = res.get('Contents', [])

    history_by_date = {}

    for obj in contents:
        key = obj['Key']
        if key.endswith('_incident.json'):
            try:
                data = s3_client.get_object(Bucket=BUCKET_SUPERVISOR_APP, Key=key)
                content = json.loads(data['Body'].read().decode('utf-8'))
                date_val = content.get('date') or key.split('/')[-2]

                # Generate pre-signed URL for companion PDF if present
                pdf_key = key.replace('_incident.json', '_report.pdf')
                pdf_url = s3_client.generate_presigned_url(
                    'get_object',
                    Params={'Bucket': BUCKET_SUPERVISOR_APP, 'Key': pdf_key},
                    ExpiresIn=1800
                )
                content['reportPdfUrl'] = pdf_url

                if date_val not in history_by_date:
                    history_by_date[date_val] = []
                history_by_date[date_val].append(content)
            except Exception as e:
                print(f"Error reading incident report {key}: {e}")

    return build_response(200, {'success': True, 'history': history_by_date})


# ─────────────────────────────────────────────────────────────────────────────
# 7. Student Exam History Handlers
# ─────────────────────────────────────────────────────────────────────────────
def handle_get_student_exam_history(params):
    """
    Lists uploaded answer sheets for a student from wilp-fr-model bucket.
    Matches S3ExamHistoryService.fetchStudentExamHistory()
    Returns list of items with metadata and pre-signed view URLs.
    """
    student_id = str(params.get('studentId', '')).strip().lower()
    if not student_id:
        return build_response(400, {'success': False, 'error': 'Missing studentId'})

    prefix = f"Exam-answers/{student_id}/"
    res = s3_client.list_objects_v2(Bucket=BUCKET_ANSWERS, Prefix=prefix)
    contents = res.get('Contents', [])

    exams = []
    for obj in contents:
        key = obj['Key']
        if key.endswith('.pdf'):
            parts = key.split('/')
            # Expected format: Exam-answers/{studentId}/{Date}/{CourseCode}/question-{Slot}.pdf
            if len(parts) >= 5:
                date_str = parts[2]
                course_code = parts[3]
                filename = parts[4]
                slot = filename.replace('question-', '').replace('.pdf', '')

                # Fetch page count from S3 metadata
                head = s3_client.head_object(Bucket=BUCKET_ANSWERS, Key=key)
                page_count = head.get('Metadata', {}).get('pages', '1')

                # Pre-signed view URL (valid for 30 minutes)
                view_url = s3_client.generate_presigned_url(
                    'get_object',
                    Params={'Bucket': BUCKET_ANSWERS, 'Key': key},
                    ExpiresIn=1800
                )

                exams.append({
                    'key': key,
                    'studentId': student_id,
                    'courseCode': course_code,
                    'slot': slot,
                    'examDate': date_str,
                    'lastModified': obj['LastModified'].isoformat(),
                    'pageCount': int(page_count) if str(page_count).isdigit() else 1,
                    'viewUrl': view_url
                })

    # Sort descending by last modified
    exams.sort(key=lambda x: x['lastModified'], reverse=True)
    return build_response(200, {'success': True, 'exams': exams})


def handle_batch_check_completed_answers(params):
    """
    Rapidly checks if students have uploaded answer sheets for a specific course & date in S3.
    Uses concurrent thread pool to check prefixes without downloading metadata or generating pre-signed URLs.
    Returns: {'success': True, 'completedIds': ['ID1', 'ID2']}
    """
    student_ids = params.get('studentIds') or []
    if isinstance(student_ids, str):
        student_ids = [student_ids]

    course_code = str(params.get('courseCode', '')).strip().upper().replace(' ', '')
    dates = params.get('dates') or []
    if not dates:
        now = datetime.now()
        dates = [now.strftime('%Y-%m-%d'), now.strftime('%d-%m-%Y')]
    elif isinstance(dates, str):
        dates = [dates]

    clean_student_ids = [str(sid).strip().lower() for sid in student_ids if str(sid).strip()]
    if not clean_student_ids:
        return build_response(200, {'success': True, 'completedIds': []})

    completed_ids = set()

    def check_student(sid):
        try:
            # 1. Fast check directly by date & course prefix
            for d in dates:
                if course_code:
                    prefix = f"Exam-answers/{sid}/{d}/{course_code}/"
                    res = s3_client.list_objects_v2(Bucket=BUCKET_ANSWERS, Prefix=prefix, MaxKeys=1)
                    if res.get('Contents'):
                        return sid.upper()
                else:
                    prefix = f"Exam-answers/{sid}/{d}/"
                    res = s3_client.list_objects_v2(Bucket=BUCKET_ANSWERS, Prefix=prefix, MaxKeys=1)
                    if res.get('Contents'):
                        return sid.upper()

            # 2. Broader fallback check under student's root folder matching key substrings
            prefix = f"Exam-answers/{sid}/"
            res = s3_client.list_objects_v2(Bucket=BUCKET_ANSWERS, Prefix=prefix, MaxKeys=30)
            for obj in res.get('Contents', []):
                key = obj.get('Key', '')
                if key.endswith('.pdf'):
                    k_upper = key.upper()
                    date_match = any(d in key for d in dates)
                    course_match = (not course_code) or (course_code in k_upper)
                    if date_match and course_match:
                        return sid.upper()
        except Exception as e:
            logger.warning(f"Error checking answers for {sid}: {e}")
        return None

    with ThreadPoolExecutor(max_workers=min(len(clean_student_ids), 12)) as executor:
        for r in executor.map(check_student, clean_student_ids):
            if r:
                completed_ids.add(r)

    return build_response(200, {
        'success': True,
        'completedIds': sorted(list(completed_ids))
    })



# ─────────────────────────────────────────────────────────────────────────────
# 8. Question Slots Handler
# ─────────────────────────────────────────────────────────────────────────────
def handle_get_question_slots(params):
    """Lists question slots from wilp-fr-model/Question_bank/{courseCode}_{date}/questions/"""
    course_code = str(params.get('courseCode', '')).strip()
    date_str = str(params.get('date', '')).strip()
    if not course_code or not date_str:
        return build_response(400, {'success': False, 'error': 'Missing courseCode or date'})

    prefix = f"Question_bank/{course_code}_{date_str}/questions/"
    res = s3_client.list_objects_v2(Bucket=BUCKET_ANSWERS, Prefix=prefix)
    contents = res.get('Contents', [])
    slots = set()

    for obj in contents:
        k = obj['Key']
        if k == prefix:
            continue
        filename = k.split('/')[-1]
        if filename:
            slot_name = filename.split('.')[0]
            if slot_name:
                slots.add(slot_name)

    if not slots:
        res_delim = s3_client.list_objects_v2(Bucket=BUCKET_ANSWERS, Prefix=prefix, Delimiter='/')
        for cp in res_delim.get('CommonPrefixes', []):
            parts = cp['Prefix'].strip('/').split('/')
            if parts and parts[-1].startswith('Q'):
                slots.add(parts[-1])

    def sort_key(s):
        nums = re.findall(r'\d+', s)
        return int(nums[0]) if nums else 0

    sorted_slots = sorted(list(slots), key=sort_key)
    return build_response(200, {'success': True, 'slots': sorted_slots})


# ─────────────────────────────────────────────────────────────────────────────
# 9. Tab Switch Violations Handlers
# ─────────────────────────────────────────────────────────────────────────────
def _parse_timeout_content(content):
    data = {}
    for line in content.split('\n'):
        if ':' in line:
            parts = line.split(':', 1)
            k = parts[0].strip()
            v = parts[1].strip()
            if k in ('Student ID', 'Course', 'Question ID', 'Exam Date', 'Timeout Time'):
                data[k] = v
    return data


def handle_get_tabswitch_violations(params):
    """
    Fetches tabswitch violations or timeouts for specific student(s) from bitswilp-data bucket.
    Filters strictly by today's date and the active course code so historic logs are never returned.
    """
    student_id = params.get('studentId')
    student_ids = params.get('studentIds') or []
    if student_id:
        student_ids = [student_id]

    student_ids = [str(s).strip().lower() for s in student_ids if s]
    logs = []

    root_prefix = str(params.get('rootPrefix') or params.get('prefix') or 'tabswitch_violation/').strip()
    if not root_prefix.endswith('/'):
        root_prefix += '/'

    # Target date tuple (day, month, year)
    date_param = params.get('date') or params.get('dates')
    if isinstance(date_param, list) and date_param:
        date_param = date_param[0]
    target_tuple = normalize_date_tuple(date_param)
    if not target_tuple:
        now_ist = datetime.now(timezone.utc) + timedelta(hours=5, minutes=30)
        target_tuple = (now_ist.day, now_ist.month, now_ist.year)

    date_candidates = [
        f"{target_tuple[2]:04d}-{target_tuple[1]:02d}-{target_tuple[0]:02d}",
        f"{target_tuple[0]:02d}-{target_tuple[1]:02d}-{target_tuple[2]:04d}"
    ]

    target_course = get_base_course_code(params.get('courseCode', ''))

    if not student_ids:
        # List student folders under root_prefix
        res = s3_client.list_objects_v2(Bucket=BUCKET_WILP_DATA, Prefix=root_prefix, Delimiter='/')
        for cp in res.get('CommonPrefixes', []):
            parts = cp['Prefix'].strip('/').split('/')
            if len(parts) >= 2:
                student_ids.append(parts[-1].lower())

    seen_keys = set()
    for sid in student_ids:
        sid_variants = list(dict.fromkeys([sid, sid.lower(), sid.upper()]))
        for s_cand in sid_variants:
            for d in date_candidates:
                prefix = f"{root_prefix}{s_cand}/{d}/"
                try:
                    res = s3_client.list_objects_v2(Bucket=BUCKET_WILP_DATA, Prefix=prefix)
                    for obj in res.get('Contents', []):
                        key = obj['Key']
                        if not key.endswith('.txt') or key in seen_keys:
                            continue
                        seen_keys.add(key)

                        # Filter course from S3 key if courseCode is provided
                        # Key pattern: {rootPrefix}/{sid}/{date}/{courseCode}/...
                        parts = key.split('/')
                        if len(parts) >= 5 and not parts[3].endswith('.txt') and target_course:
                            key_course = get_base_course_code(parts[3])
                            if key_course and key_course != target_course:
                                continue

                        try:
                            txt_obj = s3_client.get_object(Bucket=BUCKET_WILP_DATA, Key=key)
                            content = txt_obj['Body'].read().decode('utf-8', errors='ignore')
                            parsed = _parse_timeout_content(content)
                            if not parsed:
                                parsed = {'Student ID': sid.upper()}
                            else:
                                parsed['Student ID'] = parsed.get('Student ID') or sid.upper()

                            # Check date inside file if present
                            if parsed.get('Exam Date'):
                                f_tuple = normalize_date_tuple(parsed.get('Exam Date'))
                                if f_tuple and f_tuple != target_tuple:
                                    continue
                            # Check course inside file if present
                            if target_course and parsed.get('Course'):
                                c_base = get_base_course_code(parsed.get('Course'))
                                if c_base and c_base != target_course:
                                    continue

                            if not parsed.get('Timeout Time'):
                                parsed['Timeout Time'] = obj['LastModified'].strftime('%H:%M:%S')
                            logs.append(parsed)
                        except Exception as err:
                            logger.warning(f"Error parsing violation log {key}: {err}")
                except Exception as e:
                    logger.warning(f"Error listing prefix {prefix}: {e}")

    return build_response(200, {'success': True, 'logs': logs})


def handle_count_violations(params):
    """Counts students who have tabswitch violations for today's active exam session."""
    student_ids = [str(s).strip().lower() for s in (params.get('studentIds') or []) if s]
    now = datetime.now(timezone.utc)
    dates = params.get('dates') or [now.strftime('%Y-%m-%d'), now.strftime('%d-%m-%Y')]

    count = 0
    for sid in student_ids:
        for d in dates:
            prefix = f"tabswitch_violation/{sid}/{d}/"
            res = s3_client.list_objects_v2(Bucket=BUCKET_WILP_DATA, Prefix=prefix, MaxKeys=1)
            if res.get('Contents'):
                count += 1
                break

    return build_response(200, {'success': True, 'count': count})


# ─────────────────────────────────────────────────────────────────────────────
# 10. Exam Schedule & Student Attendance Consolidations (BITS-exam.csv & ExamDetails.csv)
# ─────────────────────────────────────────────────────────────────────────────

def normalize_date_tuple(d_str):
    """
    Parses any date string (YYYY-MM-DD, DD-MM-YYYY, with / or -) into (day, month, year).
    Returns None if no valid date found.
    """
    if not d_str:
        return None
    d_str = str(d_str).strip()
    m_iso = re.search(r'(\d{4})[-/](\d{1,2})[-/](\d{1,2})', d_str)
    if m_iso:
        return (int(m_iso.group(3)), int(m_iso.group(2)), int(m_iso.group(1)))
    m_dmy = re.search(r'(\d{1,2})[-/](\d{1,2})[-/](\d{4})', d_str)
    if m_dmy:
        return (int(m_dmy.group(1)), int(m_dmy.group(2)), int(m_dmy.group(3)))
    return None


def get_base_course_code(code):
    """Extracts base course code ignoring suffixes and whitespace: 'DUMMZA111-EC3R' -> 'DUMMZA111'"""
    if not code:
        return ''
    return str(code).split('-')[0].strip().upper().replace(' ', '')


def format_course_code(code):
    """Ensures a space after the 4-character discipline code if missing: 'DUMMZA111' -> 'DUMM ZA111'"""
    code = str(code).strip().upper()
    if ' ' in code:
        return code
    if len(code) > 4:
        return code[:4] + ' ' + code[4:]
    return code


def normalize_time(t):
    if not t:
        return ''
    parts = str(t).strip().split(':')
    return f"{parts[0]}:{parts[1]}:00" if len(parts) == 2 else str(t).strip()


def get_center_timings_data(centre_name):
    try:
        table = dynamodb.Table(TABLE_CENTER_TIMINGS)
        res = table.get_item(Key={'exam-hall': centre_name.strip()})
        item = res.get('Item')
        if not item:
            scan_res = table.scan(FilterExpression=Attr('exam-hall').eq(centre_name.strip()))
            items = scan_res.get('Items', [])
            if items:
                item = items[0]
        return item
    except Exception as e:
        logger.warning(f"Error getting center timings for {centre_name}: {e}")
        return None


def get_session_times(timings, session):
    if not timings:
        return '', ''
    s = str(session).upper()
    start = normalize_time(timings.get(f'{s}_start') or timings.get(f'{s} Start') or '')
    end = normalize_time(timings.get(f'{s}_end') or timings.get(f'{s} End') or '')
    return start, end


def get_center_session_registrations(centre, date_str, session):
    try:
        data = s3_client.get_object(Bucket=BUCKET_EXAM_APP, Key='student_details/BITS-exam.csv')['Body'].read().decode('utf-8')
        reader = csv.reader(StringIO(data))
        try:
            raw_headers = next(reader)
        except StopIteration:
            return set(), set()
        
        headers = [h.strip() for h in raw_headers]
        headers_upper = [h.upper() for h in headers]

        bits_id_col = next((i for i, h in enumerate(headers_upper) if h in ('BITS ID', 'BITSID', 'BITS_ID')), 0)
        centre_col = next((i for i, h in enumerate(headers_upper) if h in ('CENTER', 'CENTRE', 'CENTERCODE')), None)
        exam_date_col = next((i for i, h in enumerate(headers_upper) if h in ('EXAMDATE', 'DATE')), None)
        course_code_col = next((i for i, h in enumerate(headers_upper) if h in ('COURSECODE', 'COURSE CODE')), None)
        session_col = next((i for i, h in enumerate(headers_upper) if h in ('SESSIONTYPE', 'SESSION')), None)

        is_flat_csv = (exam_date_col is not None and course_code_col is not None)

        registered_students = set()
        active_courses = set()
        target_tuple = normalize_date_tuple(date_str)

        for row in reader:
            if not row or len(row) <= centre_col:
                continue
            if row[centre_col].strip().upper() != centre.strip().upper():
                continue

            student_id = row[bits_id_col].strip().upper() if len(row) > bits_id_col else None
            if not student_id:
                continue

            if is_flat_csv:
                r_date = row[exam_date_col].strip() if len(row) > exam_date_col else ''
                r_course = row[course_code_col].strip() if len(row) > course_code_col else ''
                r_session = row[session_col].strip().upper() if (session_col is not None and len(row) > session_col) else 'FN'
                if normalize_date_tuple(r_date) == target_tuple:
                    if session_col is None or r_session == session.upper():
                        clean_course = get_base_course_code(r_course)
                        if clean_course:
                            registered_students.add(student_id)
                            active_courses.add(clean_course)
            else:
                for i, h in enumerate(headers):
                    if normalize_date_tuple(h) == target_tuple:
                        tokens = re.split(r'[_ /-]+', h.upper())
                        col_session = 'FN'
                        for p in tokens:
                            if p in ('FN', 'AN', 'EN'):
                                col_session = p
                                break
                        if col_session == session.upper():
                            if len(row) > i and row[i].strip():
                                clean_course = get_base_course_code(row[i])
                                if clean_course:
                                    registered_students.add(student_id)
                                    active_courses.add(clean_course)

        return registered_students, active_courses
    except Exception as e:
        logger.error(f"Error in get_center_session_registrations: {e}")
        return set(), set()


def handle_center_exams(params):
    """
    Returns today's exam course codes for the specified exam center across FN, AN, and EN sessions.
    Strictly filters BITS-exam.csv for today's date so exams from other dates are never included.
    """
    try:
        centre = (params.get('centre') or params.get('center') or '').strip()
        date_str = (params.get('date') or params.get('examDate') or '').strip()
        
        if not centre:
            return build_response(400, {'success': False, 'error': 'Missing centre'})

        # Target date tuple (day, month, year)
        target_tuple = normalize_date_tuple(date_str)
        if not target_tuple:
            # Default to today in IST (UTC+5:30)
            now_ist = datetime.now(timezone.utc) + timedelta(hours=5, minutes=30)
            target_tuple = (now_ist.day, now_ist.month, now_ist.year)

        # Load master CSV from S3
        csv_obj = s3_client.get_object(Bucket=BUCKET_EXAM_APP, Key='student_details/BITS-exam.csv')
        csv_content = csv_obj['Body'].read().decode('utf-8')
        reader = csv.reader(StringIO(csv_content))
        
        try:
            raw_headers = next(reader)
        except StopIteration:
            return build_response(200, {'success': True, 'exams': []})

        headers = [h.strip() for h in raw_headers]
        headers_upper = [h.upper() for h in headers]

        centre_col = next((i for i, h in enumerate(headers_upper) if h in ('CENTER', 'CENTRE', 'CENTERCODE')), None)
        if centre_col is None:
            return build_response(500, {'success': False, 'error': 'Centre column not found in BITS-exam.csv'})

        exam_date_col = next((i for i, h in enumerate(headers_upper) if h in ('EXAMDATE', 'DATE')), None)
        course_code_col = next((i for i, h in enumerate(headers_upper) if h in ('COURSECODE', 'COURSE CODE')), None)
        session_col = next((i for i, h in enumerate(headers_upper) if h in ('SESSIONTYPE', 'SESSION')), None)
        is_flat_csv = (exam_date_col is not None and course_code_col is not None)

        matching_cols = []
        if not is_flat_csv:
            # Header-based columns: find columns whose header matches today's date
            for idx, h in enumerate(headers):
                col_date_tuple = normalize_date_tuple(h)
                if col_date_tuple == target_tuple:
                    tokens = re.split(r'[_ /-]+', h.upper())
                    col_session = None
                    for s in ('FN', 'AN', 'EN'):
                        if s in tokens:
                            col_session = s
                            break
                    if not col_session:
                        for s in ('FN', 'AN', 'EN'):
                            if s in h.upper():
                                col_session = s
                                break
                    matching_cols.append({
                        'col': idx,
                        'session': col_session or 'FN'
                    })

        exams_set = set()
        target_centre_upper = centre.upper()

        for row in reader:
            if not row or len(row) <= centre_col:
                continue
            row_centre = row[centre_col].strip().upper()
            if row_centre != target_centre_upper:
                continue

            if is_flat_csv:
                r_date_str = row[exam_date_col].strip() if len(row) > exam_date_col else ''
                if normalize_date_tuple(r_date_str) == target_tuple:
                    c_code = re.sub(r'\s+', ' ', row[course_code_col].strip().upper()) if len(row) > course_code_col else ''
                    s_type = row[session_col].strip().upper() if (session_col is not None and len(row) > session_col) else 'FN'
                    if s_type not in ('FN', 'AN', 'EN'):
                        s_type = 'FN'
                    if c_code:
                        exams_set.add((c_code, s_type))
            else:
                for mc in matching_cols:
                    col_idx = mc['col']
                    if len(row) > col_idx:
                        c_code = re.sub(r'\s+', ' ', row[col_idx].strip().upper())
                        if c_code:
                            exams_set.add((c_code, mc['session']))

        result = []
        for code, sess in exams_set:
            result.append({
                'courseCode': code,
                'session': sess
            })

        prio_map = {'FN': 1, 'AN': 2, 'EN': 3}
        result.sort(key=lambda x: (prio_map.get(x['session'], 9), x['courseCode']))

        return build_response(200, {
            'success': True,
            'exams': result,
            'totalExams': len(result),
            'centre': centre,
            'date': f"{target_tuple[0]:02d}-{target_tuple[1]:02d}-{target_tuple[2]:04d}"
        })
    except Exception as e:
        logger.error(f"Error in handle_center_exams: {e}")
        return build_response(500, {'success': False, 'error': str(e)})


def handle_attendance_status(params):
    """
    Returns registered students and their live attendance status for a specific course, session, and center.
    Uses ThreadPoolExecutor for fast parallel DynamoDB querying.
    """
    try:
        centre = (params.get('centre') or params.get('center') or '').strip()
        course_code = (params.get('courseCode') or '').strip().upper()
        session = (params.get('session') or '').strip().upper()
        date_str = (params.get('date') or params.get('examDate') or '').strip()

        if not all([centre, course_code, session]):
            return build_response(400, {'success': False, 'error': 'Missing centre, courseCode, or session'})

        target_tuple = normalize_date_tuple(date_str)
        if not target_tuple:
            now_ist = datetime.now(timezone.utc) + timedelta(hours=5, minutes=30)
            target_tuple = (now_ist.day, now_ist.month, now_ist.year)

        target_date_dd_mm = f"{target_tuple[0]:02d}-{target_tuple[1]:02d}-{target_tuple[2]:04d}"

        # 1. Load Master CSV to find registered students
        csv_obj = s3_client.get_object(Bucket=BUCKET_EXAM_APP, Key='student_details/BITS-exam.csv')
        csv_content = csv_obj['Body'].read().decode('utf-8')
        reader = csv.reader(StringIO(csv_content))
        
        try:
            raw_headers = next(reader)
        except StopIteration:
            return build_response(200, {'success': True, 'total': 0, 'present': 0, 'students': []})

        headers = [h.strip() for h in raw_headers]
        headers_upper = [h.upper() for h in headers]

        bits_id_col = next((i for i, h in enumerate(headers_upper) if h in ('BITS ID', 'BITSID', 'BITS_ID')), 0)
        name_col = next((i for i, h in enumerate(headers_upper) if h in ('NAME', 'STUDENTNAME', 'STUDENT_NAME')), None)
        centre_col = next((i for i, h in enumerate(headers_upper) if h in ('CENTER', 'CENTRE', 'CENTERCODE')), None)
        exam_date_col = next((i for i, h in enumerate(headers_upper) if h in ('EXAMDATE', 'DATE')), None)
        course_code_col = next((i for i, h in enumerate(headers_upper) if h in ('COURSECODE', 'COURSE CODE')), None)
        session_col = next((i for i, h in enumerate(headers_upper) if h in ('SESSIONTYPE', 'SESSION')), None)

        is_flat_csv = (exam_date_col is not None and course_code_col is not None)

        registered_students = []
        seen_student_ids = set()
        clean_target_course = get_base_course_code(course_code)

        matching_cols = []
        if not is_flat_csv:
            for idx, h in enumerate(headers):
                if normalize_date_tuple(h) == target_tuple:
                    tokens = re.split(r'[_ /-]+', h.upper())
                    col_sess = 'FN'
                    for s in ('FN', 'AN', 'EN'):
                        if s in tokens:
                            col_sess = s
                            break
                    if col_sess == session:
                        matching_cols.append(idx)

        for row in reader:
            if not row or len(row) <= centre_col:
                continue
            if row[centre_col].strip().upper() != centre.upper():
                continue

            sid = row[bits_id_col].strip().upper() if len(row) > bits_id_col else ''
            if not sid or sid in seen_student_ids:
                continue

            sname = row[name_col].strip() if (name_col is not None and len(row) > name_col) else 'Unknown'

            if is_flat_csv:
                r_date_str = row[exam_date_col].strip() if len(row) > exam_date_col else ''
                if normalize_date_tuple(r_date_str) == target_tuple:
                    r_sess = row[session_col].strip().upper() if (session_col is not None and len(row) > session_col) else 'FN'
                    if r_sess == session:
                        r_course = row[course_code_col].strip().upper() if len(row) > course_code_col else ''
                        if get_base_course_code(r_course) == clean_target_course:
                            registered_students.append({'studentId': sid, 'studentName': sname})
                            seen_student_ids.add(sid)
            else:
                for col_idx in matching_cols:
                    if len(row) > col_idx and row[col_idx].strip():
                        r_course = row[col_idx].strip().upper()
                        if get_base_course_code(r_course) == clean_target_course:
                            registered_students.append({'studentId': sid, 'studentName': sname})
                            seen_student_ids.add(sid)
                            break

        # 2. Query student attendance in bits-attendance-details in parallel
        attendance_table = dynamodb.Table(TABLE_STUDENT_ATTENDANCE)

        def check_student_status(student):
            sid = student['studentId']
            sid_db = sid.lower()
            try:
                res = attendance_table.query(
                    KeyConditionExpression=Key('bitsId').eq(sid_db)
                )
                items = res.get('Items', [])
                for item in items:
                    item_date = item.get('examDate') or item.get('loginDate')
                    if normalize_date_tuple(item_date) == target_tuple:
                        item_sess = str(item.get('sessionType', '')).upper()
                        if not item_sess or item_sess == session:
                            item_course = str(item.get('courseCode', '')).upper()
                            if get_base_course_code(item_course) == clean_target_course:
                                finished_time = str(item.get('finished', '00:00:00'))
                                if finished_time != '00:00:00' and finished_time != '99:99:99':
                                    return (student, 'Completed')
                                else:
                                    return (student, 'In Progress')
            except Exception as query_err:
                logger.warning(f"Error querying student {sid}: {query_err}")
            return (student, 'Not Started')

        with ThreadPoolExecutor(max_workers=10) as executor:
            check_results = list(executor.map(check_student_status, registered_students))

        status_list = []
        completed_count = 0
        in_progress_count = 0

        for student, status in check_results:
            if status == 'Completed':
                completed_count += 1
            elif status == 'In Progress':
                in_progress_count += 1
            status_list.append({
                'studentId': student['studentId'],
                'studentName': student['studentName'],
                'status': status
            })

        status_sort_order = {'Completed': 0, 'In Progress': 1, 'Not Started': 2}
        status_list.sort(key=lambda x: (status_sort_order.get(x['status'], 3), x['studentName']))

        return build_response(200, {
            'success': True,
            'total': len(registered_students),
            'present': completed_count,
            'inProgress': in_progress_count,
            'students': status_list,
            'debug': {
                'registered_count': len(registered_students),
                'target_course': course_code,
                'target_date': target_date_dd_mm,
                'session': session
            }
        })
    except Exception as e:
        logger.error(f"Error in handle_attendance_status: {e}")
        return build_response(500, {'success': False, 'error': str(e)})


def handle_session_history(params):
    """
    Fetches answer sheet upload history for registered students in the active or nearest session.
    """
    try:
        centre = (params.get('centre') or params.get('center') or '').strip()
        date_str = (params.get('date') or params.get('examDate') or '').strip()
        if not centre:
            return build_response(400, {'success': False, 'error': 'Missing centre'})

        timings = get_center_timings_data(centre)
        if not timings:
            return build_response(404, {'success': False, 'error': f'Center timings not found for {centre}'})

        offset = timedelta(hours=5, minutes=30)
        now_local = datetime.now(timezone.utc) + offset
        current_time = now_local.strftime('%H:%M:%S')

        target_tuple = normalize_date_tuple(date_str)
        if not target_tuple:
            target_tuple = (now_local.day, now_local.month, now_local.year)

        target_date_ymd = f"{target_tuple[2]:04d}-{target_tuple[1]:02d}-{target_tuple[0]:02d}"
        target_date_dmy = f"{target_tuple[0]:02d}-{target_tuple[1]:02d}-{target_tuple[2]:04d}"

        valid_sessions = []
        for s in ['FN', 'AN', 'EN']:
            start, end = get_session_times(timings, s)
            if start and end:
                valid_sessions.append({'session': s, 'start': start, 'end': end})

        if not valid_sessions:
            return build_response(200, {
                'success': True,
                'session': 'None',
                'data': [],
                'message': 'No exam timings configured for this center.'
            })

        valid_sessions.sort(key=lambda x: x['start'])
        session = None
        for vs in valid_sessions:
            if vs['start'] <= current_time <= vs['end']:
                session = vs['session']
                break

        if not session:
            if current_time < valid_sessions[0]['start']:
                session = valid_sessions[0]['session']
            else:
                for vs in reversed(valid_sessions):
                    if current_time >= vs['end'] or current_time >= vs['start']:
                        session = vs['session']
                        break
                if not session:
                    session = valid_sessions[-1]['session']

        registered_students, active_courses = get_center_session_registrations(centre, target_date_dmy, session)

        results = []
        for student_id in registered_students:
            for d_str in [target_date_ymd, target_date_dmy]:
                prefix = f"Exam-answers/{student_id.lower()}/{d_str}/"
                try:
                    res = s3_client.list_objects_v2(Bucket=BUCKET_ANSWERS, Prefix=prefix)
                    contents = res.get('Contents', [])
                    for obj in contents:
                        key = obj['Key']
                        parts = key.split('/')
                        if len(parts) >= 4:
                            c_code = get_base_course_code(parts[3])
                            if not active_courses or c_code in active_courses:
                                last_mod_utc = obj['LastModified']
                                last_mod_local = last_mod_utc + offset
                                upload_time = last_mod_local.strftime('%H:%M:%S')

                                head = s3_client.head_object(Bucket=BUCKET_ANSWERS, Key=key)
                                pages = head.get('Metadata', {}).get('pages', '0')
                                results.append({
                                    'studentId': student_id,
                                    'courseCode': parts[3],
                                    'fileName': parts[-1],
                                    'pageCount': pages,
                                    'uploadTime': upload_time
                                })
                except Exception as s3_err:
                    logger.warning(f"Error querying S3 prefix {prefix}: {s3_err}")

        return build_response(200, {
            'success': True,
            'session': session,
            'date': target_date_dmy,
            'data': results,
            'currentTime': current_time
        })
    except Exception as e:
        logger.error(f"Error in handle_session_history: {e}")
        return build_response(500, {'success': False, 'error': str(e)})


def handle_save_scanned_qr(payload):
    """
    Saves student verification details from supervisor QR scan into Bits-Supervisor-Confirmation.
    """
    try:
        bits_id = str(payload.get('bitsId', '')).strip().lower()
        if not bits_id:
            return build_response(400, {'success': False, 'error': 'Missing bitsId'})

        timing_raw = str(payload.get('examTiming', ''))
        date_raw = str(payload.get('examDate', ''))
        
        timing_digits = re.sub(r'\D', '', timing_raw)
        date_digits = re.sub(r'\D', '', date_raw)
        scanned_id_val = f"{bits_id}_{timing_digits}{date_digits}"
        
        table = dynamodb.Table(TABLE_SUPERVISOR_CONFIRMATION)
        item = {
            'bitsId': bits_id,
            'scannedId': scanned_id_val,
            'name': str(payload.get('name', '')).strip(),
            'organization': str(payload.get('organization', '')).strip(),
            'center': str(payload.get('center', '')).strip(),
            'courseCode': str(payload.get('courseCode', '')).strip(),
            'courseName': str(payload.get('courseName', '')).strip(),
            'examDate': date_raw.strip(),
            'examTiming': timing_raw.strip(),
            'scannedtime': str(payload.get('scannedtime', '')).strip(),
            'scanneddate': str(payload.get('scanneddate', '')).strip(),
            'supervisorId': str(payload.get('supervisorId', '')).strip()
        }
        table.put_item(Item=item)
        return build_response(200, {'success': True, 'message': 'Student verification details saved successfully'})
    except Exception as e:
        logger.error(f"Error in handle_save_scanned_qr: {e}")
        return build_response(500, {'success': False, 'error': str(e)})


def handle_student_exam_details(student_id):
    """
    Looks up student information and today's exams from BITS-exam.csv and ExamDetails.csv.
    """
    try:
        student_id = str(student_id).strip().upper()

        exam_details_map = {}
        try:
            exam_resp = s3_client.get_object(Bucket=BUCKET_EXAM_APP, Key='exam_details/ExamDetails.csv')
            exam_content = exam_resp['Body'].read().decode('utf-8')
            exam_reader = csv.reader(StringIO(exam_content))
            exam_headers = [h.strip().upper() for h in next(exam_reader)]
            cc_col = next((i for i, h in enumerate(exam_headers) if 'COURSE' in h and 'CODE' in h), None)
            type_col = next((i for i, h in enumerate(exam_headers) if 'EXAM' in h and 'TYPE' in h), None)
            for row in exam_reader:
                if cc_col is not None and len(row) > cc_col:
                    code = row[cc_col].strip().upper().replace(' ', '')
                    etype = row[type_col].strip() if (type_col is not None and len(row) > type_col) else ''
                    exam_details_map[code] = etype
        except Exception as e:
            logger.warning(f"Could not load ExamDetails.csv: {e}")

        bits_resp = s3_client.get_object(Bucket=BUCKET_EXAM_APP, Key='student_details/BITS-exam.csv')
        bits_content = bits_resp['Body'].read().decode('utf-8')
        bits_reader = csv.reader(StringIO(bits_content))
        bits_headers = [h.strip() for h in next(bits_reader)]
        bits_headers_upper = [h.upper() for h in bits_headers]

        bits_id_col = next((i for i, h in enumerate(bits_headers_upper) if 'BITS' in h and 'ID' in h), 0)
        name_col = next((i for i, h in enumerate(bits_headers_upper) if h in ('NAME', 'STUDENTNAME')), None)
        centre_col = next((i for i, h in enumerate(bits_headers_upper) if h in ('CENTER', 'CENTRE', 'CENTERCODE')), None)

        now_ist = datetime.now(timezone.utc) + timedelta(hours=5, minutes=30)
        today_tuple = (now_ist.day, now_ist.month, now_ist.year)

        exam_cols = []
        for idx, h in enumerate(bits_headers):
            if normalize_date_tuple(h) == today_tuple:
                parts = h.split('_')
                exam_cols.append({
                    'col': idx,
                    'examNumber': parts[0] if len(parts) >= 3 else 'C1',
                    'date': f"{today_tuple[0]:02d}-{today_tuple[1]:02d}-{today_tuple[2]:04d}",
                    'session': parts[2] if len(parts) >= 3 else 'FN'
                })

        for row in bits_reader:
            if len(row) > bits_id_col and row[bits_id_col].strip().upper() == student_id:
                s_name = row[name_col].strip() if name_col is not None and len(row) > name_col else 'Unknown'
                centre = row[centre_col].strip() if centre_col is not None and len(row) > centre_col else 'Unknown'
                timings = get_center_timings_data(centre)
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
                return build_response(200, {
                    'success': True,
                    'studentId': student_id,
                    'studentName': s_name,
                    'centre': centre,
                    'exams': exams
                })

        return build_response(404, {'success': False, 'error': 'Student not found'})
    except Exception as e:
        logger.error(f"Error in handle_student_exam_details: {e}")
        return build_response(500, {'success': False, 'error': str(e)})


def handle_course_name_lookup(params):
    """Looks up course name for a given course code in ExamDetails.csv."""
    try:
        course_code = params.get('courseCode', '').strip().upper()
        data = s3_client.get_object(Bucket=BUCKET_EXAM_APP, Key='exam_details/ExamDetails.csv')['Body'].read().decode('utf-8')
        reader = csv.reader(StringIO(data))
        headers = [h.strip().upper() for h in next(reader)]
        cc_col = next((i for i, h in enumerate(headers) if 'COURSECODE' in h.replace(' ','')), None)
        cn_col = next((i for i, h in enumerate(headers) if 'COURSENAME' in h.replace(' ','')), None)
        
        for row in reader:
            if len(row) > max(cc_col, cn_col) and row[cc_col].strip().upper() == course_code:
                return build_response(200, {'success': True, 'courseName': row[cn_col].strip()})
        return build_response(404, {'success': False, 'error': 'Course not found'})
    except Exception as e:
        return build_response(500, {'success': False, 'error': str(e)})


def handle_student_ids_by_date(params):
    """Returns student IDs who have exams on the specified date from BITS-exam.csv."""
    try:
        date_str = params.get('date', '')
        target_tuple = normalize_date_tuple(date_str)
        data = s3_client.get_object(Bucket=BUCKET_EXAM_APP, Key='student_details/BITS-exam.csv')['Body'].read().decode('utf-8')
        reader = csv.reader(StringIO(data))
        headers = [h.strip().upper() for h in next(reader)]
        bits_id_col = next((i for i, h in enumerate(headers) if 'BITS' in h and 'ID' in h), 0)
        
        matching_cols = []
        if target_tuple:
            for i, h in enumerate(headers):
                if normalize_date_tuple(h) == target_tuple:
                    matching_cols.append(i)
        
        ids = set()
        for row in reader:
            if len(row) > bits_id_col and row[bits_id_col].strip():
                if not matching_cols or any(len(row) > c and row[c].strip() for c in matching_cols):
                    ids.add(row[bits_id_col].strip().upper())
        
        return build_response(200, {'success': True, 'studentIds': sorted(list(ids))})
    except Exception as e:
        return build_response(500, {'success': False, 'error': str(e)})


def handle_all_student_ids():
    """Returns all student IDs from BITS-exam.csv and S3 Exam-answers prefixes."""
    try:
        all_ids = set()
        try:
            data = s3_client.get_object(Bucket=BUCKET_EXAM_APP, Key='student_details/BITS-exam.csv')['Body'].read().decode('utf-8')
            reader = csv.reader(StringIO(data))
            headers = [h.strip().upper() for h in next(reader)]
            bits_id_col = next((i for i, h in enumerate(headers) if 'BITS' in h and 'ID' in h), 0)
            for row in reader:
                if len(row) > bits_id_col and row[bits_id_col].strip():
                    all_ids.add(row[bits_id_col].strip().upper())
        except Exception as csv_err:
            logger.warning(f"CSV Load Error in handle_all_student_ids: {csv_err}")

        try:
            paginator = s3_client.get_paginator('list_objects_v2')
            for page in paginator.paginate(Bucket=BUCKET_ANSWERS, Prefix='Exam-answers/', Delimiter='/'):
                for prefix in page.get('CommonPrefixes', []):
                    folder_name = prefix.get('Prefix', '').split('/')[-2]
                    if folder_name and folder_name != 'Exam-answers':
                        all_ids.add(folder_name.upper())
        except Exception as s3_err:
            logger.warning(f"S3 Prefix Error in handle_all_student_ids: {s3_err}")

        return build_response(200, {'success': True, 'studentIds': sorted(list(all_ids))})
    except Exception as e:
        return build_response(500, {'success': False, 'error': str(e)})


def handle_s3_upload_event(event):
    """Processes S3 PDF upload triggers into finishedTable."""
    try:
        import urllib.parse
        finished_table = dynamodb.Table(TABLE_FINISHED)
        attendance_table = dynamodb.Table(TABLE_STUDENT_ATTENDANCE)
        
        for record in event.get('Records', []):
            bucket = record['s3']['bucket']['name']
            key = urllib.parse.unquote_plus(record['s3']['object']['key'])
            
            parts = key.split('/')
            if len(parts) < 5 or parts[0] != 'Exam-answers':
                continue
                
            student_id = parts[1].strip().lower()
            date_str = parts[2].strip()
            course_code_raw = parts[3].strip()
            filename = parts[4].strip()
            
            course_code = course_code_raw.upper().replace(' ', '')
            
            db_date = date_str
            target_tuple = normalize_date_tuple(date_str)
            if target_tuple:
                db_date = f"{target_tuple[0]:02d}-{target_tuple[1]:02d}-{target_tuple[2]:04d}"
            
            q_match = re.search(r'Q(\d+)', filename)
            if not q_match:
                continue
            q_num = int(q_match.group(1))
            
            head = s3_client.head_object(Bucket=bucket, Key=key)
            page_count = head.get('Metadata', {}).get('pages', '1')
            
            res = attendance_table.query(KeyConditionExpression=Key('bitsId').eq(student_id))
            items = res.get('Items', [])
            
            matching_attendance_id = None
            clean_code = get_base_course_code(course_code)
            for item in items:
                item_date = item.get('examDate') or item.get('loginDate')
                if normalize_date_tuple(item_date) == target_tuple:
                    if get_base_course_code(item.get('courseCode', '')) == clean_code:
                        matching_attendance_id = item.get('attendanceId')
                        break
            
            if not matching_attendance_id:
                continue
                
            question_field = f"question{q_num}"
            try:
                finished_table.update_item(
                    Key={
                        'bitsId': student_id,
                        'attendanceId': matching_attendance_id
                    },
                    UpdateExpression=f"SET {question_field} = :page_count",
                    ExpressionAttributeValues={
                        ':page_count': str(page_count)
                    },
                    ConditionExpression='attribute_exists(bitsId)'
                )
            except Exception as update_err:
                logger.warning(f"Error updating finishedTable: {update_err}")
                
        return {'success': True, 'message': 'Processed S3 records'}
    except Exception as e:
        logger.error(f"Unhandled error in handle_s3_upload_event: {e}")
        return {'success': False, 'error': str(e)}



