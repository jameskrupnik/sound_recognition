part of 'main.dart';

class _AppBar extends StatelessWidget implements PreferredSizeWidget {
  const _AppBar();

  @override
  Size get preferredSize => const Size.fromHeight(kToolbarHeight * 2);

  @override
  Widget build(BuildContext context) {
    return AppBar(
      title: const Text('sound_recognition'),
      bottom: const TabBar(
        tabs: [
          Tab(text: 'Live'),
          Tab(text: 'Hunt'),
        ],
      ),
    );
  }
}
