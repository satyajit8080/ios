import Foundation
import HealthKit
import Observation

@MainActor
@Observable
final class HealthKitManager {
    enum Status: Equatable {
        case unavailable
        case notRequested
        case authorized
        case denied
    }

    var status: Status = .notRequested
    var lastSync: Date?
    var syncError: String?

    private let store = HKHealthStore()

    private var readTypes: Set<HKObjectType> {
        var types: Set<HKObjectType> = []
        if let steps = HKQuantityType.quantityType(forIdentifier: .stepCount) { types.insert(steps) }
        if let distance = HKQuantityType.quantityType(forIdentifier: .distanceWalkingRunning) { types.insert(distance) }
        if let energy = HKQuantityType.quantityType(forIdentifier: .activeEnergyBurned) { types.insert(energy) }
        if let mass = HKQuantityType.quantityType(forIdentifier: .bodyMass) { types.insert(mass) }
        return types
    }

    private var writeTypes: Set<HKSampleType> {
        var types: Set<HKSampleType> = []
        if let mass = HKQuantityType.quantityType(forIdentifier: .bodyMass) { types.insert(mass) }
        if let water = HKQuantityType.quantityType(forIdentifier: .dietaryWater) { types.insert(water) }
        if let energy = HKQuantityType.quantityType(forIdentifier: .dietaryEnergyConsumed) { types.insert(energy) }
        return types
    }

    func requestAuthorization() async {
        guard HKHealthStore.isHealthDataAvailable() else {
            status = .unavailable
            return
        }
        do {
            try await store.requestAuthorization(toShare: writeTypes, read: readTypes)
            status = .authorized
        } catch {
            status = .denied
            syncError = "Health access wasn't granted. You can still log steps manually."
        }
    }

    /// Pulls the last `days` of step data and pushes it to the API.
    @discardableResult
    func syncSteps(days: Int = 30) async -> StepStats? {
        guard HKHealthStore.isHealthDataAvailable(),
              let stepType = HKQuantityType.quantityType(forIdentifier: .stepCount) else { return nil }

        let calendar = Calendar.current
        let end = calendar.startOfDay(for: Date()).addingTimeInterval(86_400)
        guard let start = calendar.date(byAdding: .day, value: -days, to: calendar.startOfDay(for: Date())) else {
            return nil
        }

        async let stepBuckets = collect(type: stepType, unit: .count(), start: start, end: end)
        async let distanceBuckets = collectOptional(identifier: .distanceWalkingRunning, unit: .meter(), start: start, end: end)
        async let energyBuckets = collectOptional(identifier: .activeEnergyBurned, unit: .kilocalorie(), start: start, end: end)

        let steps = await stepBuckets
        let distance = await distanceBuckets
        let energy = await energyBuckets

        let items = steps.map { day, value in
            StepSyncItem(
                recordedOn: day,
                steps: Int(value),
                distanceM: distance[day] ?? 0,
                activeKcal: energy[day] ?? 0
            )
        }
        guard !items.isEmpty else { return nil }

        do {
            let stats: StepStats = try await APIClient.shared.post(
                "steps/sync", body: StepSyncRequest(items: items, source: "healthkit")
            )
            lastSync = Date()
            syncError = nil
            return stats
        } catch {
            syncError = error.localizedDescription
            return nil
        }
    }

    func latestBodyMassKg() async -> Double? {
        guard let type = HKQuantityType.quantityType(forIdentifier: .bodyMass) else { return nil }
        return await withCheckedContinuation { continuation in
            let sort = NSSortDescriptor(key: HKSampleSortIdentifierEndDate, ascending: false)
            let query = HKSampleQuery(sampleType: type, predicate: nil, limit: 1, sortDescriptors: [sort]) { _, samples, _ in
                let value = (samples?.first as? HKQuantitySample)?
                    .quantity.doubleValue(for: .gramUnit(with: .kilo))
                continuation.resume(returning: value)
            }
            store.execute(query)
        }
    }

    func writeWeight(_ kilograms: Double, on date: Date = Date()) {
        guard let type = HKQuantityType.quantityType(forIdentifier: .bodyMass) else { return }
        let quantity = HKQuantity(unit: .gramUnit(with: .kilo), doubleValue: kilograms)
        let sample = HKQuantitySample(type: type, quantity: quantity, start: date, end: date)
        store.save(sample) { _, _ in }
    }

    func writeWater(millilitres: Int, on date: Date = Date()) {
        guard let type = HKQuantityType.quantityType(forIdentifier: .dietaryWater) else { return }
        let quantity = HKQuantity(unit: .literUnit(with: .milli), doubleValue: Double(millilitres))
        let sample = HKQuantitySample(type: type, quantity: quantity, start: date, end: date)
        store.save(sample) { _, _ in }
    }

    func writeCalories(_ kcal: Double, on date: Date = Date()) {
        guard let type = HKQuantityType.quantityType(forIdentifier: .dietaryEnergyConsumed) else { return }
        let quantity = HKQuantity(unit: .kilocalorie(), doubleValue: kcal)
        let sample = HKQuantitySample(type: type, quantity: quantity, start: date, end: date)
        store.save(sample) { _, _ in }
    }

    // MARK: - Statistics collection

    private func collectOptional(
        identifier: HKQuantityTypeIdentifier, unit: HKUnit, start: Date, end: Date
    ) async -> [Date: Double] {
        guard let type = HKQuantityType.quantityType(forIdentifier: identifier) else { return [:] }
        return await collect(type: type, unit: unit, start: start, end: end)
    }

    private func collect(type: HKQuantityType, unit: HKUnit, start: Date, end: Date) async -> [Date: Double] {
        await withCheckedContinuation { continuation in
            let interval = DateComponents(day: 1)
            let predicate = HKQuery.predicateForSamples(withStart: start, end: end, options: .strictStartDate)
            let query = HKStatisticsCollectionQuery(
                quantityType: type,
                quantitySamplePredicate: predicate,
                options: .cumulativeSum,
                anchorDate: Calendar.current.startOfDay(for: start),
                intervalComponents: interval
            )
            query.initialResultsHandler = { _, results, _ in
                var output: [Date: Double] = [:]
                results?.enumerateStatistics(from: start, to: end) { statistics, _ in
                    if let sum = statistics.sumQuantity() {
                        let day = Calendar.current.startOfDay(for: statistics.startDate)
                        output[day] = sum.doubleValue(for: unit)
                    }
                }
                continuation.resume(returning: output)
            }
            store.execute(query)
        }
    }
}

// MARK: - Background sync

extension HealthKitManager {
    /// Registers observer queries so Health can wake the app when new samples land.
    ///
    /// `enableBackgroundDelivery` is what makes this work when the app isn't running;
    /// without it the observer only fires while the app is foregrounded. Requires the
    /// `HealthKit` background-delivery entitlement and the `processing` background mode.
    func startBackgroundSync() {
        guard HKHealthStore.isHealthDataAvailable(), status == .authorized else { return }

        if let stepType = HKQuantityType.quantityType(forIdentifier: .stepCount) {
            observe(stepType, frequency: .hourly) { [weak self] in
                await self?.syncSteps(days: 3)
            }
        }

        if let massType = HKQuantityType.quantityType(forIdentifier: .bodyMass) {
            observe(massType, frequency: .immediate) { [weak self] in
                await self?.importWeightFromHealth()
            }
        }
    }

    private func observe(
        _ type: HKQuantityType,
        frequency: HKUpdateFrequency,
        handler: @escaping @Sendable () async -> Void
    ) {
        let query = HKObserverQuery(sampleType: type, predicate: nil) { _, completionHandler, error in
            // completionHandler must be called even on failure, or HealthKit will
            // keep retrying and eventually stop delivering updates altogether.
            guard error == nil else {
                completionHandler()
                return
            }
            Task {
                await handler()
                completionHandler()
            }
        }
        store.execute(query)

        store.enableBackgroundDelivery(for: type, frequency: frequency) { success, error in
            if let error, !success {
                Task { @MainActor [weak self] in
                    self?.syncError = "Background Health sync couldn't start: \(error.localizedDescription)"
                }
            }
        }
    }

    /// Pulls any weight samples Health has that we haven't logged yet.
    ///
    /// Samples this app wrote are filtered out, otherwise a weigh-in logged in the app
    /// would be read straight back and re-posted in a loop.
    @discardableResult
    func importWeightFromHealth(days: Int = 14) async -> Int {
        guard HKHealthStore.isHealthDataAvailable(),
              status == .authorized,
              let massType = HKQuantityType.quantityType(forIdentifier: .bodyMass) else { return 0 }

        let calendar = Calendar.current
        let start = calendar.date(byAdding: .day, value: -days, to: calendar.startOfDay(for: Date())) ?? Date()
        let timeRange = HKQuery.predicateForSamples(withStart: start, end: Date(), options: .strictStartDate)
        let notFromThisApp = NSCompoundPredicate(
            notPredicateWithSubpredicate: HKQuery.predicateForObjects(from: HKSource.default())
        )
        let predicate = NSCompoundPredicate(andPredicateWithSubpredicates: [timeRange, notFromThisApp])

        let samples: [HKQuantitySample] = await withCheckedContinuation { continuation in
            let query = HKSampleQuery(
                sampleType: massType,
                predicate: predicate,
                limit: HKObjectQueryNoLimit,
                sortDescriptors: [NSSortDescriptor(key: HKSampleSortIdentifierEndDate, ascending: true)]
            ) { _, results, _ in
                continuation.resume(returning: (results as? [HKQuantitySample]) ?? [])
            }
            store.execute(query)
        }

        guard !samples.isEmpty else { return 0 }

        // One reading per day — the last of the day wins, matching how the backend
        // stores weight (a unique row per user per date).
        var latestPerDay: [Date: HKQuantitySample] = [:]
        for sample in samples {
            let day = calendar.startOfDay(for: sample.endDate)
            if let existing = latestPerDay[day], existing.endDate >= sample.endDate { continue }
            latestPerDay[day] = sample
        }

        var imported = 0
        for (day, sample) in latestPerDay.sorted(by: { $0.key < $1.key }) {
            let kilograms = sample.quantity.doubleValue(for: .gramUnit(with: .kilo))
            guard kilograms > 20, kilograms < 400 else { continue }

            let body: [String: AnyEncodable] = [
                "weight_kg": AnyEncodable(kilograms),
                "recorded_on": AnyEncodable(DateFormatter.awlcDay.string(from: day)),
                "note": AnyEncodable("Imported from Health")
            ]
            if (try? await APIClient.shared.postVoid("weight", body: body)) != nil {
                imported += 1
            }
        }

        if imported > 0 { lastSync = Date() }
        return imported
    }

    /// Full sync used on launch and on foreground: steps and weight together.
    func syncAll() async {
        _ = await syncSteps(days: 30)
        _ = await importWeightFromHealth()
    }
}
