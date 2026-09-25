import 'package:flutter/material.dart';

class ProjectsScreen extends StatelessWidget {
  const ProjectsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF070D12),

      appBar: AppBar(
        backgroundColor: const Color(0xFF070D12),
        elevation: 0,
        centerTitle: true,
        title: const Text(
          'Projects',
          style: TextStyle(
            color: Colors.white,
            fontSize: 19,
            fontWeight: FontWeight.w700,
          ),
        ),
        iconTheme: const IconThemeData(
          color: Colors.white,
        ),
      ),

      body: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          children: [
            Container(
              height: 48,
              decoration: BoxDecoration(
                color: const Color(0xFF121A21),
                borderRadius:
                BorderRadius.circular(12),
              ),
              child: const Row(
                children: [
                  SizedBox(width: 15),
                  Icon(
                    Icons.search_rounded,
                    color: Colors.white54,
                  ),
                  SizedBox(width: 12),
                  Text(
                    'Search my projects...',
                    style: TextStyle(
                      color: Colors.white38,
                    ),
                  ),
                ],
              ),
            ),

            const SizedBox(height: 20),

            Expanded(
              child: GridView.builder(
                itemCount: 6,
                gridDelegate:
                const SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: 2,
                  crossAxisSpacing: 12,
                  mainAxisSpacing: 12,
                  childAspectRatio: 0.92,
                ),
                itemBuilder: (context, index) {
                  final names = [
                    'Riverfront Bridge',
                    'Green Valley',
                    'Skyline Heights',
                    'City Center',
                    'Modern Villas',
                    'Urban Square',
                  ];

                  return _project(
                    names[index],
                    index,
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _project(String title, int index) {
    return Container(
      decoration: BoxDecoration(
        color: const Color(0xFF111920),
        borderRadius: BorderRadius.circular(13),
        border: Border.all(
          color: Colors.white.withOpacity(0.05),
        ),
      ),
      child: Column(
        crossAxisAlignment:
        CrossAxisAlignment.start,
        children: [
          Expanded(
            child: ClipRRect(
              borderRadius:
              const BorderRadius.vertical(
                top: Radius.circular(13),
              ),
              child: Container(
                width: double.infinity,
                color: const Color(0xFF1B2730),
                child: const Icon(
                  Icons.apartment_rounded,
                  color: Color(0xFFD4A843),
                  size: 45,
                ),
              ),
            ),
          ),

          Padding(
            padding: const EdgeInsets.all(11),
            child: Text(
              title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 13,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }
}