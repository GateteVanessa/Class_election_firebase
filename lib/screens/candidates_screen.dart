import 'package:flutter/material.dart';
import '../logic/election_logic.dart';
import '../models/candidate.dart';

class CandidatesScreen extends StatefulWidget {
  final Election election;
  const CandidatesScreen({super.key, required this.election});

  @override
  State<CandidatesScreen> createState() => _CandidatesScreenState();
}

class _CandidatesScreenState extends State<CandidatesScreen> {
  final controller = TextEditingController();

  void show(String message) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  void add() {
    final error = widget.election.addCandidate(controller.text);
    if (error == null) {
      controller.clear();
      show('Candidate added');
    } else {
      show(error);
    }
  }

  // Step 5, edit: change the name of a candidate (an update in Firestore).
  Future<void> edit(Candidate c) async {
    final nameController = TextEditingController(text: c.name);
    final newName = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Edit candidate'),
        content: TextField(
          controller: nameController,
          autofocus: true,
          textCapitalization: TextCapitalization.words,
          decoration: const InputDecoration(labelText: 'Name'),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Cancel')),
          FilledButton(
              onPressed: () => Navigator.pop(ctx, nameController.text),
              child: const Text('Save')),
        ],
      ),
    );
    nameController.dispose();
    if (newName == null) return;
    final error = widget.election.renameCandidate(c, newName);
    show(error ?? 'Candidate updated');
  }

  // Step 5, delete: ask first, then remove the document.
  Future<void> confirmDelete(Candidate c) async {
    final yes = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Are you sure?'),
        content: Text('Remove ${c.name}?'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancel')),
          FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Remove')),
        ],
      ),
    );
    if (yes != true) return;
    final error = widget.election.removeCandidate(c);
    if (error != null) show(error);
  }

  Future<void> confirmReset() async {
    final yes = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Are you sure?'),
        content: const Text('This clears every vote and every voter.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancel')),
          FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Reset')),
        ],
      ),
    );
    if (yes == true) {
      widget.election.reset();
      show('All votes cleared');
    }
  }

  @override
  void dispose() {
    controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: widget.election,
      builder: (context, _) {
        final candidates = widget.election.candidates;
        return Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            children: [
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: controller,
                      decoration: const InputDecoration(
                        labelText: 'New candidate',
                        border: OutlineInputBorder(),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  FilledButton(onPressed: add, child: const Text('Add')),
                ],
              ),
              const SizedBox(height: 12),
              Expanded(
                child: candidates.isEmpty
                    ? const Center(
                    child: Text(
                        'No candidates yet.\nType a name above and tap Add.',
                        textAlign: TextAlign.center))
                    : ListView.builder(
                  itemCount: candidates.length,
                  itemBuilder: (context, i) {
                    final c = candidates[i];
                    return Card(
                      child: ListTile(
                        leading: const Icon(Icons.person),
                        title: Text(c.name),
                        subtitle: Text('${c.votes} votes'),
                        trailing: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            IconButton(
                              icon: const Icon(Icons.edit),
                              tooltip: 'Edit',
                              onPressed: () => edit(c),
                            ),
                            IconButton(
                              icon: const Icon(Icons.delete),
                              tooltip: 'Remove',
                              onPressed: () => confirmDelete(c),
                            ),
                          ],
                        ),
                      ),
                    );
                  },
                ),
              ),
              OutlinedButton.icon(
                onPressed: confirmReset,
                icon: const Icon(Icons.restart_alt),
                label: const Text('Reset all votes'),
              ),
            ],
          ),
        );
      },
    );
  }
}