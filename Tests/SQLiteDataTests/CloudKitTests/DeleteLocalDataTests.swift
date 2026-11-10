#if canImport(CloudKit)
  import CloudKit
  import SQLiteData
  import Testing

  extension BaseCloudKitTests {
    @MainActor
    final class DeleteLocalDataTests: BaseCloudKitTests, @unchecked Sendable {
      @available(iOS 17, macOS 14, tvOS 17, watchOS 10, *)
      @Test func failedDeleteThrowsAndLeavesEngineStopped() async throws {
        try await userDatabase.userWrite { db in
          try db.seed {
            RemindersList(id: 1, title: "Personal")
            Reminder(id: 1, title: "Get milk", remindersListID: 1)
          }
        }
        try await syncEngine.processPendingRecordZoneChanges(scope: .private)

        // NB: Emulates a delete that fails on disk (e.g. the disk is full).
        try await userDatabase.userWrite { db in
          try #sql(
            """
            CREATE TRIGGER "test_fail_delete_reminders" BEFORE DELETE ON "reminders"
            BEGIN SELECT RAISE(ABORT, 'disk full'); END
            """
          )
          .execute(db)
        }

        await #expect(throws: SyncEngine.DeleteLocalDataError.self) {
          try await self.syncEngine.deleteLocalData()
        }

        #expect(!syncEngine.isRunning)
        try await userDatabase.read { db in
          try #expect(Reminder.count().fetchOne(db) == 1)
        }
        // NB: Nothing left behind is queued for upload: a running engine with a fresh
        //     metadatabase would treat every table as new and queue every remaining row.
        try await syncEngine.metadatabase.read { db in
          try #expect(SyncMetadata.count().fetchOne(db) == 0)
        }

        // A retry once the delete can succeed clears everything and starts the engine.
        try await userDatabase.userWrite { db in
          try #sql(#"DROP TRIGGER "test_fail_delete_reminders""#).execute(db)
        }
        try await syncEngine.deleteLocalData()

        #expect(syncEngine.isRunning)
        try await userDatabase.read { db in
          try #expect(RemindersList.count().fetchOne(db) == 0)
          try #expect(Reminder.count().fetchOne(db) == 0)
        }
        try await syncEngine.processPendingDatabaseChanges(scope: .private)
      }
    }
  }
#endif
