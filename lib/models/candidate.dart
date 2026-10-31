import 'package:cloud_firestore/cloud_firestore.dart';

class Candidate {
  final String id; // the Firestore document id
  final String name;
  int votes;

  Candidate({this.id = '', required this.name, this.votes = 0});

  // Only the facts are saved. Percentages, ranking and the winner are
  // calculated every time, so they can never be wrong.
  Map<String, dynamic> toMap() {
    return {'name': name, 'votes': votes};
  }

  factory Candidate.fromDoc(DocumentSnapshot<Map<String, dynamic>> doc) {
    final data = doc.data()!;
    return Candidate(
      id: doc.id,
      name: data['name'] as String,
      votes: (data['votes'] as num?)?.toInt() ?? 0,
    );
  }
}