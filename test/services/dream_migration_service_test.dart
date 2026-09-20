import 'dart:convert';

import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:aiwellnesspal/services/dream_migration_service.dart';
import 'package:aiwellnesspal/models/dream.dart';
import 'package:aiwellnesspal/models/wellness_intention.dart';

/// A minimal fake FirebaseAuth for testing.
/// Uses a simple approach to provide a non-null currentUser.
class _FakeFirebaseAuth extends Fake implements FirebaseAuth {
  final String uid;
  _FakeFirebaseAuth(this.uid);

  @override
  User? get currentUser => _FakeUser(uid);
}

class _FakeUser extends Fake implements User {
  @override
  final String uid;
  _FakeUser(this.uid);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const testUid = 'test_user_123';

  late FakeFirebaseFirestore fakeFirestore;
  late _FakeFirebaseAuth fakeAuth;
  late DreamMigrationService service;

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    fakeFirestore = FakeFirebaseFirestore();
    fakeAuth = _FakeFirebaseAuth(testUid);
    service = DreamMigrationService(
      firestore: fakeFirestore,
      auth: fakeAuth,
    );
  });

  group('DreamMigrationService', () {
    test('migrates local dreams to Firestore wellness_intentions', () async {
      // Arrange: populate local dreams
      final dreams = [
        Dream(id: 'dream_1', title: 'Learn Yoga', description: 'Flexibility goal'),
        Dream(id: 'dream_2', title: 'Run Marathon', description: 'Endurance goal'),
      ];
      SharedPreferences.setMockInitialValues({
        'aiwellnesspal_dreams': jsonEncode(dreams.map((d) => d.toMap()).toList()),
      });

      // Act
      await service.migrate();

      // Assert: check Firestore has the intentions
      final snapshot = await fakeFirestore
          .collection('users')
          .doc(testUid)
          .collection('wellness_intentions')
          .get();

      expect(snapshot.docs.length, 2);

      final ids = snapshot.docs.map((doc) => doc.id).toSet();
      expect(ids, contains('dream_1'));
      expect(ids, contains('dream_2'));

      // Verify the migrated data preserves fields
      final doc1 = snapshot.docs.firstWhere((d) => d.id == 'dream_1');
      expect(doc1.data()['title'], 'Learn Yoga');
      expect(doc1.data()['description'], 'Flexibility goal');
      expect(doc1.data()['category'], 'general');
      expect(doc1.data()['isActive'], true);
    });

    test('does not run migration if flag is already set', () async {
      // Arrange: set flag as already done
      SharedPreferences.setMockInitialValues({
        'wellness_migration_v1_done': true,
        'aiwellnesspal_dreams': jsonEncode([
          Dream(id: 'dream_x', title: 'Should Not Migrate').toMap(),
        ]),
      });

      // Act
      await service.migrate();

      // Assert: no intentions written
      final snapshot = await fakeFirestore
          .collection('users')
          .doc(testUid)
          .collection('wellness_intentions')
          .get();

      expect(snapshot.docs.length, 0);
    });

    test('skips dreams that already exist as intentions in Firestore', () async {
      // Arrange: one dream already exists in Firestore
      final existingIntention = WellnessIntention.fromDream(
        Dream(id: 'dream_existing', title: 'Already Migrated'),
      );
      await fakeFirestore
          .collection('users')
          .doc(testUid)
          .collection('wellness_intentions')
          .doc('dream_existing')
          .set(existingIntention.toMap());

      // Local dreams include both existing and new
      final dreams = [
        Dream(id: 'dream_existing', title: 'Already Migrated'),
        Dream(id: 'dream_new', title: 'New Dream'),
      ];
      SharedPreferences.setMockInitialValues({
        'aiwellnesspal_dreams': jsonEncode(dreams.map((d) => d.toMap()).toList()),
      });

      // Act
      await service.migrate();

      // Assert: only the new one is added (existing stays)
      final snapshot = await fakeFirestore
          .collection('users')
          .doc(testUid)
          .collection('wellness_intentions')
          .get();

      expect(snapshot.docs.length, 2);
      final ids = snapshot.docs.map((doc) => doc.id).toSet();
      expect(ids, contains('dream_existing'));
      expect(ids, contains('dream_new'));
    });

    test('sets migration flag after successful migration', () async {
      SharedPreferences.setMockInitialValues({
        'aiwellnesspal_dreams': jsonEncode([
          Dream(id: 'd1', title: 'Test').toMap(),
        ]),
      });

      await service.migrate();

      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getBool('wellness_migration_v1_done'), true);
    });

    test('handles empty local dreams gracefully', () async {
      SharedPreferences.setMockInitialValues({
        'aiwellnesspal_dreams': jsonEncode([]),
      });

      // Should not throw
      await service.migrate();

      final snapshot = await fakeFirestore
          .collection('users')
          .doc(testUid)
          .collection('wellness_intentions')
          .get();

      expect(snapshot.docs.length, 0);

      // Still marks migration as done
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getBool('wellness_migration_v1_done'), true);
    });

    test('handles missing aiwellnesspal_dreams key gracefully', () async {
      SharedPreferences.setMockInitialValues({});

      await service.migrate();

      final snapshot = await fakeFirestore
          .collection('users')
          .doc(testUid)
          .collection('wellness_intentions')
          .get();

      expect(snapshot.docs.length, 0);

      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getBool('wellness_migration_v1_done'), true);
    });

    test('preserves all Dream fields during migration', () async {
      final dream = Dream(
        id: 'full_dream',
        title: 'Complete Dream',
        description: 'Full description',
        startDate: DateTime(2024, 1, 15),
        deadline: DateTime(2024, 6, 30),
        themeColor: 0xFF42A5F5,
        themeIcon: 0xE87C,
        backgroundImagePath: '/images/bg.png',
      );

      SharedPreferences.setMockInitialValues({
        'aiwellnesspal_dreams': jsonEncode([dream.toMap()]),
      });

      await service.migrate();

      final snapshot = await fakeFirestore
          .collection('users')
          .doc(testUid)
          .collection('wellness_intentions')
          .get();

      expect(snapshot.docs.length, 1);
      final data = snapshot.docs.first.data();

      expect(data['id'], 'full_dream');
      expect(data['title'], 'Complete Dream');
      expect(data['description'], 'Full description');
      expect(data['startDate'], '2024-01-15T00:00:00.000');
      expect(data['deadline'], '2024-06-30T00:00:00.000');
      expect(data['themeColor'], 0xFF42A5F5);
      expect(data['themeIcon'], 0xE87C);
      expect(data['backgroundImagePath'], '/images/bg.png');
      expect(data['category'], 'general');
      expect(data['isActive'], true);
    });

    test('isMigrationCompleted returns false initially', () async {
      SharedPreferences.setMockInitialValues({});
      expect(await service.isMigrationCompleted(), false);
    });

    test('isMigrationCompleted returns true after migration', () async {
      SharedPreferences.setMockInitialValues({
        'aiwellnesspal_dreams': jsonEncode([]),
      });

      await service.migrate();
      expect(await service.isMigrationCompleted(), true);
    });
  });
}
