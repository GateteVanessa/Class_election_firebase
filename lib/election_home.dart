import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import 'logic/election_logic.dart';
import 'screens/candidates_screen.dart';
import 'screens/results_screen.dart';
import 'screens/vote_screen.dart';

/// The app after login: your three tabs, now fed live by Firestore.
class ElectionHome extends StatefulWidget {
  const ElectionHome({super.key, required this.user});
  final User user;

  @override
  State<ElectionHome> createState() => _ElectionHomeState();
}

class _ElectionHomeState extends State<ElectionHome> {
  late final Election election;
  int tab = 0;
  bool loaded = false; // false = loading state (spinner)

  @override
  void initState() {
    super.initState();
    election = Election(widget.user.uid);
    election.addListener(_showWriteError);
    start();
  }

  Future<void> start() async {
    await election.start(); // waits for the first data from Firestore
    if (!mounted) return;
    setState(() => loaded = true);
  }

  // If the server refuses a save (for example permission-denied), say so.
  void _showWriteError() {
    final message = election.takeWriteError();
    if (message == null || !mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  void dispose() {
    election.removeListener(_showWriteError);
    election.dispose();
    super.dispose();
  }

  Widget _body() {
    if (!loaded) return const Center(child: CircularProgressIndicator());

    // Error state: the rules refused, or there is no connection.
    if (election.loadError != null && election.candidates.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Text('Could not load your election.\n${election.loadError}',
              textAlign: TextAlign.center),
        ),
      );
    }

    final pages = [
      VoteScreen(election: election),
      ResultsScreen(election: election),
      CandidatesScreen(election: election),
    ];
    return pages[tab];
  }

  @override
  Widget build(BuildContext context) {
    const titles = ['Vote', 'Results', 'Candidates'];
    return Scaffold(
      appBar: AppBar(
        title: Text('Ijwi · ${titles[tab]}'),
        backgroundColor: const Color(0xFF3F3D9E),
        foregroundColor: Colors.white,
        actions: [
          // The name typed when the account was created
          if ((widget.user.displayName ?? '').isNotEmpty)
            Center(
              child: Text(widget.user.displayName!.split(' ').first,
                  style: const TextStyle(color: Colors.white)),
            ),
          IconButton(
            icon: const Icon(Icons.logout),
            tooltip: 'Log out',
            onPressed: () => FirebaseAuth.instance.signOut(),
          ),
        ],
      ),
      body: _body(),
      bottomNavigationBar: NavigationBar(
        selectedIndex: tab,
        onDestinationSelected: (i) => setState(() => tab = i),
        destinations: const [
          NavigationDestination(icon: Icon(Icons.how_to_vote), label: 'Vote'),
          NavigationDestination(icon: Icon(Icons.bar_chart), label: 'Results'),
          NavigationDestination(icon: Icon(Icons.group), label: 'Candidates'),
        ],
      ),
    );
  }
}