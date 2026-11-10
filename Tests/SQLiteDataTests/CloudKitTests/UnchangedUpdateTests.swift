#if canImport(CloudKit)
  import CloudKit
  import Dependencies
  import Foundation
  import SQLiteData
  import Testing

  extension BaseCloudKitTests {
    @MainActor
    final class UnchangedUpdateTests: BaseCloudKitTests, @unchecked Sendable {
      @available(iOS 17, macOS 14, tvOS 17, watchOS 10, *)
      @Test func unchangedUpdateKeepsModificationTimeAndQueuesSave() async throws {
        try await userDatabase.userWrite { db in
          try db.seed {
            RemindersList(id: 1, title: "Personal")
            Reminder(id: 1, title: "Get milk", remindersListID: 1)
            RemindersListAsset(remindersListID: 1, coverImage: Data([1, 2, 3]))
          }
        }
        try await syncEngine.processPendingRecordZoneChanges(scope: .private)
        #expect(syncEngine.private.state.pendingRecordZoneChanges.isEmpty)

        try withDependencies {
          $0.currentTime.now += 60
        } operation: {
          try userDatabase.userWrite { db in
            // Text, NULL and BLOB columns written back as they are, and the primary key.
            try RemindersList.find(1).update { $0.title = "Personal" }.execute(db)
            try Reminder.find(1)
              .update {
                $0.title = "Get milk"
                $0.dueDate = #bind(nil)
                $0.priority = #bind(nil)
              }
              .execute(db)
            try RemindersListAsset.find(1).update { $0.coverImage = #bind(Data([1, 2, 3])) }.execute(db)
          }
        }

        #expect(try await modificationTime(RemindersList.recordID(for: 1)) == 0)
        #expect(try await modificationTime(Reminder.recordID(for: 1)) == 0)
        #expect(try await modificationTime(RemindersListAsset.recordID(for: 1)) == 0)
        #expect(
          Set(syncEngine.private.state.pendingRecordZoneChanges) == [
            .saveRecord(RemindersList.recordID(for: 1)),
            .saveRecord(Reminder.recordID(for: 1)),
            .saveRecord(RemindersListAsset.recordID(for: 1)),
          ]
        )
        try await syncEngine.processPendingRecordZoneChanges(scope: .private)
      }

      @available(iOS 17, macOS 14, tvOS 17, watchOS 10, *)
      @Test func changedUpdateMovesModificationTime() async throws {
        try await userDatabase.userWrite { db in
          try db.seed {
            RemindersList(id: 1, title: "Personal")
            Reminder(id: 1, title: "Get milk", remindersListID: 1)
            RemindersListAsset(remindersListID: 1, coverImage: Data([1, 2, 3]))
          }
        }
        try await syncEngine.processPendingRecordZoneChanges(scope: .private)

        try withDependencies {
          $0.currentTime.now += 60
        } operation: {
          try userDatabase.userWrite { db in
            try RemindersList.find(1).update { $0.title = "Work" }.execute(db)
            try Reminder.find(1).update { $0.priority = #bind(2) }.execute(db)
            try RemindersListAsset.find(1).update { $0.coverImage = #bind(Data([1, 2, 4])) }.execute(db)
          }
        }

        #expect(try await modificationTime(RemindersList.recordID(for: 1)) == 60)
        #expect(try await modificationTime(Reminder.recordID(for: 1)) == 60)
        #expect(try await modificationTime(RemindersListAsset.recordID(for: 1)) == 60)
        #expect(
          Set(syncEngine.private.state.pendingRecordZoneChanges) == [
            .saveRecord(RemindersList.recordID(for: 1)),
            .saveRecord(Reminder.recordID(for: 1)),
            .saveRecord(RemindersListAsset.recordID(for: 1)),
          ]
        )
        try await syncEngine.processPendingRecordZoneChanges(scope: .private)
      }

      @available(iOS 17, macOS 14, tvOS 17, watchOS 10, *)
      private func modificationTime(_ recordID: CKRecord.ID) async throws -> Int64? {
        try await syncEngine.metadatabase.read { db in
          try SyncMetadata
            .where { $0.recordName.eq(recordID.recordName) }
            .select(\.userModificationTime)
            .fetchOne(db)
        }
      }
    }
  }
#endif
