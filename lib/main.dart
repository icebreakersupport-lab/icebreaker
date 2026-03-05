import 'package:flutter/material.dart';

void main() {
  runApp(const IcebreakerApp());
}

class IcebreakerApp extends StatelessWidget {
  const IcebreakerApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Icebreaker',
      debugShowCheckedModeBanner: false,
      theme: ThemeData.dark(),
      home: const HomeScreen(),
    );
  }
}

class HomeScreen extends StatelessWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: Center(
        child: GestureDetector(
          onTap: () {
            debugPrint("Go Live tapped");
          },
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: const [
              Icon(Icons.favorite, color: Colors.pinkAccent, size: 120),
              SizedBox(height: 16),
              Text(
                "GO LIVE",
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 32,
                  fontWeight: FontWeight.bold,
                  letterSpacing: 1.2,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}