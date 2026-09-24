import 'package:flutter/material.dart';
import 'package:supervisorapp/constants/app_constants.dart';

class AppFooter extends StatelessWidget {
  const AppFooter({super.key});

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: double.infinity,
          color: Colors.white,
          padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 20),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                AppConstants.appVersion,
                style: TextStyle(
                  fontSize: 9,
                  color: const Color.fromARGB(255, 9, 0, 0),
                  fontWeight: FontWeight.w400,
                ),
              ),
              Text(
                'D & D by I.K.VAL Softwares LLP',
                style: TextStyle(
                  fontSize: 9,
                  color: const Color.fromARGB(255, 9, 0, 0),
                  fontWeight: FontWeight.w400,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}
