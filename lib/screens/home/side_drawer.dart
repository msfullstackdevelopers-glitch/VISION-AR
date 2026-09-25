import 'package:flutter/material.dart';

class SideDrawer extends StatelessWidget {
  const SideDrawer({super.key});

  @override
  Widget build(BuildContext context) {
    return Drawer(
      backgroundColor: const Color(0xFF0A1117),
      width: MediaQuery.of(context).size.width * 0.82,

      child: SafeArea(
        child: Column(
          children: [
            // Profile header
            Padding(
              padding: const EdgeInsets.fromLTRB(
                22,
                25,
                18,
                20,
              ),
              child: Row(
                children: [
                  Container(
                    width: 56,
                    height: 56,
                    decoration: BoxDecoration(
                      color: const Color(0xFFD4A843),
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(
                      Icons.person_rounded,
                      color: Colors.black,
                      size: 30,
                    ),
                  ),

                  const SizedBox(width: 14),

                  const Expanded(
                    child: Column(
                      crossAxisAlignment:
                      CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Mirza Abdullah',
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 17,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        SizedBox(height: 4),
                        Text(
                          'Explore your projects',
                          style: TextStyle(
                            color: Colors.white54,
                            fontSize: 12,
                          ),
                        ),
                      ],
                    ),
                  ),

                  IconButton(
                    onPressed: () {
                      Navigator.pop(context);
                    },
                    icon: const Icon(
                      Icons.close_rounded,
                      color: Colors.white70,
                    ),
                  ),
                ],
              ),
            ),

            Divider(
              color: Colors.white.withOpacity(0.08),
            ),

            const SizedBox(height: 10),

            _drawerItem(
              context,
              Icons.home_outlined,
              'Home',
              true,
            ),

            _drawerItem(
              context,
              Icons.folder_outlined,
              'My Projects',
              false,
            ),

            _drawerItem(
              context,
              Icons.explore_outlined,
              'Discover',
              false,
            ),

            _drawerItem(
              context,
              Icons.bookmark_border_rounded,
              'Saved Projects',
              false,
            ),

            _drawerItem(
              context,
              Icons.qr_code_scanner_rounded,
              'Scan QR',
              false,
            ),

            const Padding(
              padding: EdgeInsets.symmetric(
                horizontal: 22,
                vertical: 12,
              ),
              child: Divider(
                color: Colors.white10,
              ),
            ),

            _drawerItem(
              context,
              Icons.settings_outlined,
              'Settings',
              false,
            ),

            _drawerItem(
              context,
              Icons.help_outline_rounded,
              'Help & Support',
              false,
            ),

            const Spacer(),

            Padding(
              padding: const EdgeInsets.all(20),
              child: Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: const Color(0xFFD4A843)
                      .withOpacity(0.08),
                  borderRadius:
                  BorderRadius.circular(12),
                  border: Border.all(
                    color: const Color(0xFFD4A843)
                        .withOpacity(0.15),
                  ),
                ),
                child: const Row(
                  children: [
                    Icon(
                      Icons.info_outline_rounded,
                      color: Color(0xFFD4A843),
                    ),
                    SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        'Build and explore the future.',
                        style: TextStyle(
                          color: Colors.white70,
                          fontSize: 12,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),

            const SizedBox(height: 10),
          ],
        ),
      ),
    );
  }

  Widget _drawerItem(
      BuildContext context,
      IconData icon,
      String title,
      bool selected,
      ) {
    return Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: 12,
        vertical: 3,
      ),
      child: ListTile(
        onTap: () {
          Navigator.pop(context);
        },

        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
        ),

        tileColor: selected
            ? const Color(0xFFD4A843).withOpacity(0.12)
            : Colors.transparent,

        leading: Icon(
          icon,
          color: selected
              ? const Color(0xFFD4A843)
              : Colors.white60,
          size: 23,
        ),

        title: Text(
          title,
          style: TextStyle(
            color: selected
                ? const Color(0xFFD4A843)
                : Colors.white,
            fontSize: 14,
            fontWeight: selected
                ? FontWeight.w600
                : FontWeight.w400,
          ),
        ),
      ),
    );
  }
}