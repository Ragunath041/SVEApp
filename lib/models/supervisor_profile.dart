/// Data model representing a registered supervisor profile.
class SupervisorProfile {
  final String supervisorId;
  final String fullName;
  final String email;
  final String centre;
  final String invigilatorType;
  final String phoneNumber;
  final String city;
  final String address;
  final String? faceImageUrl;
  final Map<String, String>? imageUrls;
  final String? registeredAt;

  SupervisorProfile({
    required this.supervisorId,
    required this.fullName,
    required this.email,
    required this.centre,
    required this.invigilatorType,
    this.phoneNumber = '',
    this.city = '',
    this.address = '',
    this.faceImageUrl,
    this.imageUrls,
    this.registeredAt,
  });

  Map<String, dynamic> toJson() => {
    'supervisor_id': supervisorId,
    'full_name': fullName,
    'email': email,
    'centre': centre,
    'invigilator_type': invigilatorType,
    'phone_number': phoneNumber,
    'city': city,
    'address': address,
    'face_image_url': faceImageUrl ?? '',
    'image_urls': imageUrls ?? {},
    'registered_at': registeredAt ?? DateTime.now().toIso8601String(),
  };

  factory SupervisorProfile.fromJson(Map<String, dynamic> json) =>
      SupervisorProfile(
        supervisorId: json['supervisor_id'] ?? json['Supervisor_id'] ?? '',
        fullName: json['full_name'] ?? json['name'] ?? json['Name'] ?? '',
        email: json['email'] ?? json['Email'] ?? '',
        centre: json['centre'] ?? json['Exam hall'] ?? '',
        invigilatorType: json['invigilator_type'] ?? json['Type'] ?? '',
        phoneNumber: json['phone_number'] ?? json['PhoneNumber'] ?? '',
        city: json['city'] ?? json['City'] ?? '',
        address: json['address'] ?? json['Address'] ?? '',
        faceImageUrl: json['face_image_url'],
        imageUrls: json['image_urls'] != null
            ? Map<String, String>.from(json['image_urls'])
            : null,
        registeredAt: json['registered_at'],
      );
}
