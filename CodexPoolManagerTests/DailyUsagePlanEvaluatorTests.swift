import Testing
@testable import CodexPoolManager

struct DailyUsagePlanEvaluatorTests {

    @Test
    func plannedLimitNeverDropsBelowOnePercent() {
        #expect(DailyUsagePlanEvaluator.plannedLimitPercent(from: 0) == 1)
        #expect(DailyUsagePlanEvaluator.plannedLimitPercent(from: -30) == 1)
        #expect(DailyUsagePlanEvaluator.plannedLimitPercent(from: 25) == 25)
    }

    @Test
    func warningThresholdIsClampedToSafeRange() {
        #expect(DailyUsagePlanEvaluator.warningThresholdPercent(from: -1) == 1)
        #expect(DailyUsagePlanEvaluator.warningThresholdPercent(from: 0) == 1)
        #expect(DailyUsagePlanEvaluator.warningThresholdPercent(from: 80) == 80)
        #expect(DailyUsagePlanEvaluator.warningThresholdPercent(from: 120) == 99)
    }

    @Test
    func remainingAndExceededAreClampedCorrectly() {
        #expect(DailyUsagePlanEvaluator.remainingBudgetPercent(todayUsedPercent: 18, plannedLimitPercent: 30) == 12)
        #expect(DailyUsagePlanEvaluator.remainingBudgetPercent(todayUsedPercent: 42, plannedLimitPercent: 30) == 0)

        #expect(DailyUsagePlanEvaluator.exceededByPercent(todayUsedPercent: 18, plannedLimitPercent: 30) == 0)
        #expect(DailyUsagePlanEvaluator.exceededByPercent(todayUsedPercent: 42, plannedLimitPercent: 30) == 12)
    }

    @Test
    func warningTriggerAndAlertLevelAreComputedFromPlanAndThreshold() {
        #expect(
            DailyUsagePlanEvaluator.warningTriggerPercent(
                plannedLimitPercent: 30,
                warningThresholdPercent: 80
            ) == 24
        )
        #expect(
            DailyUsagePlanEvaluator.alertLevel(
                todayUsedPercent: 23,
                plannedLimitPercent: 30,
                warningThresholdPercent: 80
            ) == .none
        )
        #expect(
            DailyUsagePlanEvaluator.alertLevel(
                todayUsedPercent: 24,
                plannedLimitPercent: 30,
                warningThresholdPercent: 80
            ) == .warning
        )
        #expect(
            DailyUsagePlanEvaluator.alertLevel(
                todayUsedPercent: 31,
                plannedLimitPercent: 30,
                warningThresholdPercent: 80
            ) == .exceeded
        )
    }

    @Test
    func shouldNotifyOnlyWhenEnabledForCurrentAlertLevelAndNotAlreadyNotifiedToday() {
        let notified = ["scope-a|warning": "2026-05-09"]

        #expect(
            DailyUsagePlanEvaluator.shouldNotify(
                isPlanEnabled: true,
                isDesktopNotifyEnabled: true,
                alertLevel: .warning,
                scopeStorageKey: "scope-a",
                todayKey: "2026-05-09",
                notifiedDaysByScopeAndLevel: notified
            ) == false
        )

        #expect(
            DailyUsagePlanEvaluator.shouldNotify(
                isPlanEnabled: true,
                isDesktopNotifyEnabled: true,
                alertLevel: .warning,
                scopeStorageKey: "scope-b",
                todayKey: "2026-05-09",
                notifiedDaysByScopeAndLevel: notified
            ) == true
        )

        #expect(
            DailyUsagePlanEvaluator.shouldNotify(
                isPlanEnabled: true,
                isDesktopNotifyEnabled: true,
                alertLevel: .exceeded,
                scopeStorageKey: "scope-a",
                todayKey: "2026-05-09",
                notifiedDaysByScopeAndLevel: notified
            ) == true
        )

        #expect(
            DailyUsagePlanEvaluator.shouldNotify(
                isPlanEnabled: false,
                isDesktopNotifyEnabled: true,
                alertLevel: .warning,
                scopeStorageKey: "scope-b",
                todayKey: "2026-05-09",
                notifiedDaysByScopeAndLevel: notified
            ) == false
        )

        #expect(
            DailyUsagePlanEvaluator.shouldNotify(
                isPlanEnabled: true,
                isDesktopNotifyEnabled: false,
                alertLevel: .warning,
                scopeStorageKey: "scope-b",
                todayKey: "2026-05-09",
                notifiedDaysByScopeAndLevel: notified
            ) == false
        )

        #expect(
            DailyUsagePlanEvaluator.shouldNotify(
                isPlanEnabled: true,
                isDesktopNotifyEnabled: true,
                alertLevel: .none,
                scopeStorageKey: "scope-b",
                todayKey: "2026-05-09",
                notifiedDaysByScopeAndLevel: notified
            ) == false
        )
    }

    @Test
    func markNotifiedUpdatesOnlyTargetScopeAndLevel() {
        let original = ["scope-a|warning": "2026-05-08"]
        let updated = DailyUsagePlanEvaluator.markNotified(
            alertLevel: .exceeded,
            scopeStorageKey: "scope-b",
            todayKey: "2026-05-09",
            notifiedDaysByScopeAndLevel: original
        )

        #expect(updated["scope-a|warning"] == "2026-05-08")
        #expect(updated["scope-b|exceeded"] == "2026-05-09")
    }
}
