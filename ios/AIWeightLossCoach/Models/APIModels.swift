import Foundation

struct TokenPair: Codable, Sendable {
    let accessToken: String
    let refreshToken: String
    let tokenType: String
    let expiresIn: Int

    enum CodingKeys: String, CodingKey {
        case accessToken = "access_token"
        case refreshToken = "refresh_token"
        case tokenType = "token_type"
        case expiresIn = "expires_in"
    }
}

struct AppUser: Codable, Identifiable, Sendable, Equatable {
    let id: UUID
    var email: String
    var fullName: String?
    var gender: String
    var birthDate: Date?
    var heightCm: Double?
    var activityLevel: String
    var startWeightKg: Double?
    var goalWeightKg: Double?
    var weeklyGoalKg: Double
    var dailyCalorieTarget: Int
    var dailyProteinTargetG: Int
    var dailyWaterMlTarget: Int
    var dailyStepTarget: Int
    var timezone: String
    var xp: Int
    var isPremium: Bool
    var isAdmin: Bool
    var onboarded: Bool
    var premiumExpiresAt: Date?
    let createdAt: Date

    enum CodingKeys: String, CodingKey {
        case id, email, gender, timezone, xp, onboarded
        case fullName = "full_name"
        case birthDate = "birth_date"
        case heightCm = "height_cm"
        case activityLevel = "activity_level"
        case startWeightKg = "start_weight_kg"
        case goalWeightKg = "goal_weight_kg"
        case weeklyGoalKg = "weekly_goal_kg"
        case dailyCalorieTarget = "daily_calorie_target"
        case dailyProteinTargetG = "daily_protein_target_g"
        case dailyWaterMlTarget = "daily_water_ml_target"
        case dailyStepTarget = "daily_step_target"
        case isPremium = "is_premium"
        case isAdmin = "is_admin"
        case premiumExpiresAt = "premium_expires_at"
        case createdAt = "created_at"
    }
}

struct AuthResponse: Codable, Sendable {
    let user: AppUser
    let tokens: TokenPair
}

struct SeriesPoint: Codable, Sendable, Identifiable, Equatable {
    var id: String { date }
    let date: String
    let value: Double

    var day: Date { DateFormatter.awlcDay.date(from: date) ?? Date() }
}

struct Dashboard: Codable, Sendable {
    let date: Date
    let weightKg: Double?
    let weightChange7dKg: Double
    let bmi: Double?
    let bmiCategory: String?
    let goalWeightKg: Double?
    let goalProgressPct: Double
    let caloriesConsumed: Double
    let calorieTarget: Int
    let caloriesRemaining: Double
    let proteinG: Double
    let carbsG: Double
    let fatG: Double
    let waterMl: Int
    let waterTargetMl: Int
    let steps: Int
    let stepTarget: Int
    let stepStreak: Int
    let habitsDone: Int
    let habitsTotal: Int
    let xp: Int
    let level: Int
    let weightSeries: [SeriesPoint]
    let calorieSeries: [SeriesPoint]
    let stepSeries: [SeriesPoint]

    enum CodingKeys: String, CodingKey {
        case date, bmi, steps, xp, level
        case weightKg = "weight_kg"
        case weightChange7dKg = "weight_change_7d_kg"
        case bmiCategory = "bmi_category"
        case goalWeightKg = "goal_weight_kg"
        case goalProgressPct = "goal_progress_pct"
        case caloriesConsumed = "calories_consumed"
        case calorieTarget = "calorie_target"
        case caloriesRemaining = "calories_remaining"
        case proteinG = "protein_g"
        case carbsG = "carbs_g"
        case fatG = "fat_g"
        case waterMl = "water_ml"
        case waterTargetMl = "water_target_ml"
        case stepTarget = "step_target"
        case stepStreak = "step_streak"
        case habitsDone = "habits_done"
        case habitsTotal = "habits_total"
        case weightSeries = "weight_series"
        case calorieSeries = "calorie_series"
        case stepSeries = "step_series"
    }
}

struct WeightEntry: Codable, Identifiable, Sendable, Equatable {
    let id: UUID
    let weightKg: Double
    let bodyFatPct: Double?
    let note: String?
    let recordedOn: Date

    enum CodingKeys: String, CodingKey {
        case id, note
        case weightKg = "weight_kg"
        case bodyFatPct = "body_fat_pct"
        case recordedOn = "recorded_on"
    }
}

struct WeightStats: Codable, Sendable {
    let currentKg: Double?
    let startKg: Double?
    let goalKg: Double?
    let changeKg: Double
    let change7dKg: Double
    let change30dKg: Double
    let bmi: Double?
    let bmiCategory: String?
    let goalProgressPct: Double
    let trendKgPerWeek: Double
    let series: [WeightEntry]

    enum CodingKeys: String, CodingKey {
        case bmi, series
        case currentKg = "current_kg"
        case startKg = "start_kg"
        case goalKg = "goal_kg"
        case changeKg = "change_kg"
        case change7dKg = "change_7d_kg"
        case change30dKg = "change_30d_kg"
        case bmiCategory = "bmi_category"
        case goalProgressPct = "goal_progress_pct"
        case trendKgPerWeek = "trend_kg_per_week"
    }
}

struct StepDay: Codable, Identifiable, Sendable, Equatable {
    var id: Date { recordedOn }
    let recordedOn: Date
    let steps: Int
    let distanceM: Double
    let activeKcal: Double

    enum CodingKeys: String, CodingKey {
        case steps
        case recordedOn = "recorded_on"
        case distanceM = "distance_m"
        case activeKcal = "active_kcal"
    }
}

struct StepStats: Codable, Sendable {
    let today: Int
    let goal: Int
    let weekTotal: Int
    let weekAverage: Int
    let bestDay: Int
    let currentStreak: Int
    let longestStreak: Int
    let series: [StepDay]

    enum CodingKeys: String, CodingKey {
        case today, goal, series
        case weekTotal = "week_total"
        case weekAverage = "week_average"
        case bestDay = "best_day"
        case currentStreak = "current_streak"
        case longestStreak = "longest_streak"
    }
}

struct StepSyncItem: Codable, Sendable {
    let recordedOn: Date
    let steps: Int
    let distanceM: Double
    let activeKcal: Double

    enum CodingKeys: String, CodingKey {
        case steps
        case recordedOn = "recorded_on"
        case distanceM = "distance_m"
        case activeKcal = "active_kcal"
    }
}

struct StepSyncRequest: Codable, Sendable {
    let items: [StepSyncItem]
    let source: String
}

struct WaterStats: Codable, Sendable {
    let todayMl: Int
    let goalMl: Int
    let progressPct: Double
    let weekAverageMl: Int
    let currentStreak: Int
    let series: [WaterDay]

    enum CodingKeys: String, CodingKey {
        case series
        case todayMl = "today_ml"
        case goalMl = "goal_ml"
        case progressPct = "progress_pct"
        case weekAverageMl = "week_average_ml"
        case currentStreak = "current_streak"
    }
}

struct WaterDay: Codable, Identifiable, Sendable, Equatable {
    var id: String { date }
    let date: String
    let ml: Int
    var day: Date { DateFormatter.awlcDay.date(from: date) ?? Date() }
}

struct Food: Codable, Identifiable, Sendable, Equatable {
    let id: UUID
    let name: String
    let brand: String?
    let servingLabel: String
    let servingGrams: Double
    let calories: Double
    let proteinG: Double
    let carbsG: Double
    let fatG: Double
    let fiberG: Double
    let sugarG: Double

    enum CodingKeys: String, CodingKey {
        case id, name, brand, calories
        case servingLabel = "serving_label"
        case servingGrams = "serving_grams"
        case proteinG = "protein_g"
        case carbsG = "carbs_g"
        case fatG = "fat_g"
        case fiberG = "fiber_g"
        case sugarG = "sugar_g"
    }
}

struct MealLog: Codable, Identifiable, Sendable, Equatable {
    let id: UUID
    let name: String
    let mealType: String
    let quantityG: Double
    let calories: Double
    let proteinG: Double
    let carbsG: Double
    let fatG: Double
    let source: String
    let imageUrl: String?
    let recordedOn: Date
    let loggedAt: Date

    enum CodingKeys: String, CodingKey {
        case id, name, calories, source
        case mealType = "meal_type"
        case quantityG = "quantity_g"
        case proteinG = "protein_g"
        case carbsG = "carbs_g"
        case fatG = "fat_g"
        case imageUrl = "image_url"
        case recordedOn = "recorded_on"
        case loggedAt = "logged_at"
    }
}

struct MealLogCreate: Codable, Sendable {
    let name: String
    let mealType: String
    let quantityG: Double
    let calories: Double
    let proteinG: Double
    let carbsG: Double
    let fatG: Double
    var foodId: UUID?
    var source: String = "manual"

    enum CodingKeys: String, CodingKey {
        case name, calories
        case mealType = "meal_type"
        case quantityG = "quantity_g"
        case proteinG = "protein_g"
        case carbsG = "carbs_g"
        case fatG = "fat_g"
        case foodId = "food_id"
        case source
    }
}

struct DaySummary: Codable, Sendable {
    let recordedOn: Date
    let calorieTarget: Int
    let calories: Double
    let proteinG: Double
    let carbsG: Double
    let fatG: Double
    let remainingCalories: Double
    let meals: [MealLog]

    enum CodingKeys: String, CodingKey {
        case calories, meals
        case recordedOn = "recorded_on"
        case calorieTarget = "calorie_target"
        case proteinG = "protein_g"
        case carbsG = "carbs_g"
        case fatG = "fat_g"
        case remainingCalories = "remaining_calories"
    }
}

struct VisionItem: Codable, Identifiable, Sendable, Equatable {
    var id: String { name + String(calories) }
    let name: String
    let quantityG: Double
    let calories: Double
    let proteinG: Double
    let carbsG: Double
    let fatG: Double
    let confidence: Double

    enum CodingKeys: String, CodingKey {
        case name, calories, confidence
        case quantityG = "quantity_g"
        case proteinG = "protein_g"
        case carbsG = "carbs_g"
        case fatG = "fat_g"
    }
}

struct VisionResult: Codable, Sendable {
    let items: [VisionItem]
    let totalCalories: Double
    let totalProteinG: Double
    let totalCarbsG: Double
    let totalFatG: Double
    let notes: String

    enum CodingKeys: String, CodingKey {
        case items, notes
        case totalCalories = "total_calories"
        case totalProteinG = "total_protein_g"
        case totalCarbsG = "total_carbs_g"
        case totalFatG = "total_fat_g"
    }
}

struct MealPlan: Codable, Identifiable, Sendable {
    let id: UUID
    let startDate: Date
    let endDate: Date
    let kind: String
    let calorieTarget: Int
    let days: PlanDays
    let groceryList: [String: [String]]
    let createdAt: Date

    enum CodingKeys: String, CodingKey {
        case id, kind, days
        case startDate = "start_date"
        case endDate = "end_date"
        case calorieTarget = "calorie_target"
        case groceryList = "grocery_list"
        case createdAt = "created_at"
    }
}

struct PlanDays: Codable, Sendable {
    let days: [PlanDay]
    let notes: String?
}

struct PlanDay: Codable, Identifiable, Sendable {
    var id: String { date }
    let date: String
    let totalCalories: Double
    let meals: [PlanMeal]

    enum CodingKeys: String, CodingKey {
        case date, meals
        case totalCalories = "total_calories"
    }
}

struct PlanMeal: Codable, Identifiable, Sendable {
    var id: String { mealType + name }
    let mealType: String
    let name: String
    let calories: Double
    let proteinG: Double
    let carbsG: Double
    let fatG: Double
    let ingredients: [String]
    let prepMinutes: Int?
    let recipe: String?

    enum CodingKeys: String, CodingKey {
        case name, calories, ingredients, recipe
        case mealType = "meal_type"
        case proteinG = "protein_g"
        case carbsG = "carbs_g"
        case fatG = "fat_g"
        case prepMinutes = "prep_minutes"
    }
}

struct ChatMessage: Codable, Identifiable, Sendable, Equatable {
    let id: UUID
    let role: String
    let content: String
    let createdAt: Date

    enum CodingKeys: String, CodingKey {
        case id, role, content
        case createdAt = "created_at"
    }
}

struct ChatResponse: Codable, Sendable {
    let reply: ChatMessage
    let provider: String
}

struct Habit: Codable, Identifiable, Sendable, Equatable {
    let id: UUID
    let name: String
    let icon: String
    let color: String
    let targetPerDay: Int
    let archived: Bool

    enum CodingKeys: String, CodingKey {
        case id, name, icon, color, archived
        case targetPerDay = "target_per_day"
    }
}

struct HabitWithStats: Codable, Identifiable, Sendable, Equatable {
    var id: UUID { habit.id }
    let habit: Habit
    let doneToday: Int
    let currentStreak: Int
    let longestStreak: Int
    let last30Days: [Date]

    enum CodingKeys: String, CodingKey {
        case habit
        case doneToday = "done_today"
        case currentStreak = "current_streak"
        case longestStreak = "longest_streak"
        case last30Days = "last_30_days"
    }
}

struct Badge: Codable, Identifiable, Sendable, Equatable {
    var id: String { code }
    let code: String
    let name: String
    let description: String
    let icon: String
    let xpReward: Int

    enum CodingKeys: String, CodingKey {
        case code, name, description, icon
        case xpReward = "xp_reward"
    }
}

struct EarnedBadge: Codable, Identifiable, Sendable, Equatable {
    var id: String { badge.code }
    let badge: Badge
    let earnedAt: Date

    enum CodingKeys: String, CodingKey {
        case badge
        case earnedAt = "earned_at"
    }
}

struct Gamification: Codable, Sendable {
    let xp: Int
    let level: Int
    let xpIntoLevel: Int
    let xpForNextLevel: Int
    let badges: [EarnedBadge]
    let lockedBadges: [Badge]

    enum CodingKeys: String, CodingKey {
        case xp, level, badges
        case xpIntoLevel = "xp_into_level"
        case xpForNextLevel = "xp_for_next_level"
        case lockedBadges = "locked_badges"
    }
}

struct Challenge: Codable, Identifiable, Sendable, Equatable {
    let id: UUID
    let code: String
    let title: String
    let subtitle: String
    let description: String
    let kind: String
    let durationDays: Int
    let targetValue: Double
    let xpReward: Int
    let premiumOnly: Bool

    enum CodingKeys: String, CodingKey {
        case id, code, title, subtitle, description, kind
        case durationDays = "duration_days"
        case targetValue = "target_value"
        case xpReward = "xp_reward"
        case premiumOnly = "premium_only"
    }
}

struct ChallengeStatus: Codable, Identifiable, Sendable, Equatable {
    var id: UUID { challenge.id }
    let challenge: Challenge
    let joined: Bool
    let progress: Double
    let progressPct: Double
    let daysLeft: Int
    let completed: Bool
    let participants: Int

    enum CodingKeys: String, CodingKey {
        case challenge, joined, progress, completed, participants
        case progressPct = "progress_pct"
        case daysLeft = "days_left"
    }
}

struct SubscriptionStatus: Codable, Sendable {
    let isPremium: Bool
    let productId: String?
    let expiresAt: Date?
    let autoRenew: Bool
    let status: String

    enum CodingKeys: String, CodingKey {
        case status
        case isPremium = "is_premium"
        case productId = "product_id"
        case expiresAt = "expires_at"
        case autoRenew = "auto_renew"
    }
}

struct VerifyPurchaseRequest: Codable, Sendable {
    let signedTransaction: String?
    let productId: String
    let originalTransactionId: String
    let transactionId: String
    let purchaseDateMs: Int
    let expiresDateMs: Int?
    let environment: String

    enum CodingKeys: String, CodingKey {
        case environment
        case signedTransaction = "signed_transaction"
        case productId = "product_id"
        case originalTransactionId = "original_transaction_id"
        case transactionId = "transaction_id"
        case purchaseDateMs = "purchase_date_ms"
        case expiresDateMs = "expires_date_ms"
    }
}

struct TrendPoint: Codable, Identifiable, Sendable, Equatable {
    var id: String { label }
    let label: String
    let value: Double
    var day: Date { DateFormatter.awlcDay.date(from: label) ?? Date() }
}

struct AnalyticsSummary: Codable, Sendable {
    let rangeDays: Int
    let weight: [TrendPoint]
    let steps: [TrendPoint]
    let calories: [TrendPoint]
    let water: [TrendPoint]
    let habitCompletion: [TrendPoint]
    let insights: [String]

    enum CodingKeys: String, CodingKey {
        case weight, steps, calories, water, insights
        case rangeDays = "range_days"
        case habitCompletion = "habit_completion"
    }
}

struct ReminderSettings: Codable, Sendable, Equatable {
    var waterEnabled: Bool
    var waterIntervalMinutes: Int
    var dayStart: String
    var dayEnd: String
    var weighInEnabled: Bool
    var weighInTime: String
    var mealLogEnabled: Bool
    var stepNudgeEnabled: Bool
    var coachCheckinEnabled: Bool

    enum CodingKeys: String, CodingKey {
        case waterEnabled = "water_enabled"
        case waterIntervalMinutes = "water_interval_minutes"
        case dayStart = "day_start"
        case dayEnd = "day_end"
        case weighInEnabled = "weigh_in_enabled"
        case weighInTime = "weigh_in_time"
        case mealLogEnabled = "meal_log_enabled"
        case stepNudgeEnabled = "step_nudge_enabled"
        case coachCheckinEnabled = "coach_checkin_enabled"
    }
}

struct AppNotification: Codable, Identifiable, Sendable {
    let id: UUID
    let title: String
    let body: String
    let kind: String
    let sentAt: Date?
    let readAt: Date?
    let createdAt: Date

    enum CodingKeys: String, CodingKey {
        case id, title, body, kind
        case sentAt = "sent_at"
        case readAt = "read_at"
        case createdAt = "created_at"
    }
}

// MARK: - Weight prediction

struct ProjectionPoint: Codable, Identifiable, Sendable, Equatable {
    var id: String { date }
    let date: String
    let weightKg: Double

    var day: Date { DateFormatter.awlcDay.date(from: date) ?? Date() }

    enum CodingKeys: String, CodingKey {
        case date
        case weightKg = "weight_kg"
    }
}

struct WeightPrediction: Codable, Sendable {
    let hasEnoughData: Bool
    let reason: String?
    let currentKg: Double?
    let smoothedKg: Double?
    let startKg: Double?
    let goalKg: Double?
    let remainingKg: Double
    let lostKg: Double
    let trendKgPerWeek: Double
    let confidence: String
    let rSquared: Double
    let goalDate: String?
    let weeksToGoal: Int?
    let goalReachable: Bool
    let weeklyProjection: [ProjectionPoint]
    let monthlyProjection: [ProjectionPoint]
    let plateauDetected: Bool
    let notes: [String]

    var goalDay: Date? { goalDate.flatMap { DateFormatter.awlcDay.date(from: $0) } }

    enum CodingKeys: String, CodingKey {
        case reason, confidence, notes
        case hasEnoughData = "has_enough_data"
        case currentKg = "current_kg"
        case smoothedKg = "smoothed_kg"
        case startKg = "start_kg"
        case goalKg = "goal_kg"
        case remainingKg = "remaining_kg"
        case lostKg = "lost_kg"
        case trendKgPerWeek = "trend_kg_per_week"
        case rSquared = "r_squared"
        case goalDate = "goal_date"
        case weeksToGoal = "weeks_to_goal"
        case goalReachable = "goal_reachable"
        case weeklyProjection = "weekly_projection"
        case monthlyProjection = "monthly_projection"
        case plateauDetected = "plateau_detected"
    }
}

// MARK: - Daily check-in

struct CheckInQuestion: Codable, Identifiable, Sendable, Equatable {
    let id: String
    let text: String
    let type: String
    let min: Double?
    let max: Double?
    let labels: [String]?
    let options: [String]?
    let maxLength: Int?

    enum CodingKeys: String, CodingKey {
        case id, text, type, min, max, labels, options
        case maxLength = "max_length"
    }
}

struct CheckInPrompt: Codable, Sendable {
    let recordedOn: Date
    let completed: Bool
    let questions: [CheckInQuestion]
    let metrics: [String: JSONValue]
    let streak: Int

    enum CodingKeys: String, CodingKey {
        case completed, questions, metrics, streak
        case recordedOn = "recorded_on"
    }
}

struct CheckIn: Codable, Identifiable, Sendable {
    let id: UUID
    let recordedOn: Date
    let answers: [String: JSONValue]
    let mood: Int?
    let energy: Int?
    let adherence: Int?
    let summary: String?
    let recommendations: [String]
    let focus: String?
    let provider: String?
    let createdAt: Date

    enum CodingKeys: String, CodingKey {
        case id, answers, mood, energy, adherence, summary, recommendations, focus, provider
        case recordedOn = "recorded_on"
        case createdAt = "created_at"
    }
}

struct CheckInHistory: Codable, Sendable {
    let streak: Int
    let entries: [CheckIn]
}

/// Minimal JSON container so heterogeneous answer/metric payloads survive a round trip
/// without forcing a rigid Swift type on data whose shape the server owns.
enum JSONValue: Codable, Sendable, Equatable {
    case string(String)
    case number(Double)
    case bool(Bool)
    case null

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if container.decodeNil() {
            self = .null
        } else if let value = try? container.decode(Bool.self) {
            self = .bool(value)
        } else if let value = try? container.decode(Double.self) {
            self = .number(value)
        } else if let value = try? container.decode(String.self) {
            self = .string(value)
        } else {
            self = .null
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .string(let value): try container.encode(value)
        case .number(let value): try container.encode(value)
        case .bool(let value): try container.encode(value)
        case .null: try container.encodeNil()
        }
    }

    var stringValue: String? {
        switch self {
        case .string(let value): value
        case .number(let value): value == value.rounded() ? String(Int(value)) : String(format: "%.1f", value)
        case .bool(let value): value ? "Yes" : "No"
        case .null: nil
        }
    }

    var doubleValue: Double? {
        switch self {
        case .number(let value): value
        case .string(let value): Double(value)
        case .bool(let value): value ? 1 : 0
        case .null: nil
        }
    }

    var intValue: Int? { doubleValue.map(Int.init) }
}
