/// Data model representing an exam duty requirement slot for supervisors.
class SupervisorRequirementSlot {
  final String reqId;
  final String city;
  final String center;
  final String date;
  final String session;
  final int requiredCount;
  final int currentRequestCount;
  bool interested;
  bool isSubmitted;
  bool isFull;

  bool get isUnavailable => isSubmitted || isFull;

  SupervisorRequirementSlot({
    required this.reqId,
    required this.city,
    required this.center,
    required this.date,
    required this.session,
    this.requiredCount = 0,
    this.currentRequestCount = 0,
    this.interested = false,
    this.isSubmitted = false,
    this.isFull = false,
  }) : assert(city.isNotEmpty);
}
