import Foundation
import Combine

/// UserDefaults-backed settings. Services observe this and re-register themselves on change.
@MainActor
public final class SettingsStore: ObservableObject {
    public static let shared = SettingsStore()

    private let defaults: UserDefaults
    private var loading = true

    // MARK: - General

    /// The menu bar icon. Hiding it leaves the shortcuts working and Settings reachable by opening
    /// the app again, which is the only way back — so the interface has to say so.
    @Published public var showMenuBarIcon: Bool = true { didSet { persist(showMenuBarIcon, .showMenuBarIcon) } }
    @Published public var showPreview: Bool = true { didSet { persist(showPreview, .showPreview) } }
    @Published public var previewCorner: PreviewCorner = .bottomRight { didSet { persist(previewCorner.rawValue, .previewCorner) } }
    /// Seconds the preview stays up. 0 means "until dismissed".
    @Published public var previewDuration: Double = 5 { didSet { persist(previewDuration, .previewDuration) } }
    /// Longest edge of the preview thumbnail, in points.
    @Published public var previewSize: Double = 220 { didSet { persist(previewSize, .previewSize) } }
    @Published public var playCaptureSound: Bool = true { didSet { persist(playCaptureSound, .playCaptureSound) } }
    @Published public var showHUD: Bool = true { didSet { persist(showHUD, .showHUD) } }
    @Published public var launchAtLogin: Bool = false { didSet { persist(launchAtLogin, .launchAtLogin) } }
    /// Set once the first-run setup has been seen, whether it was completed or skipped.
    @Published public var hasCompletedSetup: Bool = false { didSet { persist(hasCompletedSetup, .hasCompletedSetup) } }

    // MARK: - Capture

    @Published public var saveDirectoryPath: String = SettingsStore.defaultSaveDirectory.path { didSet { persist(saveDirectoryPath, .saveDirectoryPath) } }
    /// When false, captures live in scratch until you explicitly save them — so nothing lands on
    /// the Desktop unless asked for. Off by default.
    @Published public var autoSaveToDisk: Bool = false { didSet { persist(autoSaveToDisk, .autoSaveToDisk) } }
    @Published public var filenameTemplate: String = "Screenshot {date} at {time}" { didSet { persist(filenameTemplate, .filenameTemplate) } }
    @Published public var imageFormat: ImageFormat = .png { didSet { persist(imageFormat.rawValue, .imageFormat) } }
    @Published public var includeCursor: Bool = false { didSet { persist(includeCursor, .includeCursor) } }
    @Published public var includeWindowShadow: Bool = true { didSet { persist(includeWindowShadow, .includeWindowShadow) } }
    @Published public var captureDelay: Int = 0 { didSet { persist(captureDelay, .captureDelay) } }
    @Published public var autoCopyToClipboard: Bool = false { didSet { persist(autoCopyToClipboard, .autoCopyToClipboard) } }

    // MARK: - OCR

    @Published public var lineBreakMode: LineBreakMode = .smartParagraphs { didSet { persist(lineBreakMode.rawValue, .lineBreakMode) } }
    @Published public var dehyphenate: Bool = true { didSet { persist(dehyphenate, .dehyphenate) } }
    @Published public var collapseWhitespace: Bool = true { didSet { persist(collapseWhitespace, .collapseWhitespace) } }
    @Published public var recognitionLevel: RecognitionLevelSetting = .accurate { didSet { persist(recognitionLevel.rawValue, .recognitionLevel) } }
    @Published public var automaticLanguageDetection: Bool = true { didSet { persist(automaticLanguageDetection, .automaticLanguageDetection) } }
    @Published public var recognitionLanguages: [String] = ["en-US"] { didSet { persist(recognitionLanguages, .recognitionLanguages) } }
    @Published public var usesLanguageCorrection: Bool = true { didSet { persist(usesLanguageCorrection, .usesLanguageCorrection) } }
    @Published public var customWords: [String] = [] { didSet { persist(customWords, .customWords) } }
    /// Upscale small selections before recognition. Small UI text is the common case for OCR.
    @Published public var enhanceSmallSelections: Bool = true { didSet { persist(enhanceSmallSelections, .enhanceSmallSelections) } }
    @Published public var autoCopyOCR: Bool = true { didSet { persist(autoCopyOCR, .autoCopyOCR) } }
    @Published public var showOCRReview: Bool = false { didSet { persist(showOCRReview, .showOCRReview) } }
    /// Whether an OCR capture also keeps the image around (preview + history).
    /// Whether a text grab also leaves the captured image on screen. Off: ⇧⌘O is asked for text,
    /// and a preview of a screenshot nobody asked for is a surprise, not a feature.
    @Published public var keepOCRImage: Bool = false { didSet { persist(keepOCRImage, .keepOCRImage) } }

    // MARK: - Quick actions

    @Published public var quickActionActivation: QuickActionActivation = .global { didSet { persist(quickActionActivation.rawValue, .quickActionActivation) } }
    @Published public var releaseOnAppSwitch: Bool = true { didSet { persist(releaseOnAppSwitch, .releaseOnAppSwitch) } }

    // MARK: - History

    /// The tool markup opens with, so a session carries on with whatever was used last rather than
    /// resetting to the arrow every time. Not shown in Settings; it is remembered state, not a
    /// preference to be set.
    @Published public var lastMarkupTool: String = MarkupTool.arrow.rawValue { didSet { persist(lastMarkupTool, .lastMarkupTool) } }
    /// The shape the Place tool stands in for. Kept apart from `lastMarkupTool`: leaving markup with
    /// Place selected must reopen on Place, and Place still has to know which shape it draws.
    @Published public var lastMarkupShape: String = MarkupTool.arrow.rawValue { didSet { persist(lastMarkupShape, .lastMarkupShape) } }
    @Published public var historyEnabled: Bool = true { didSet { persist(historyEnabled, .historyEnabled) } }
    @Published public var historyLimit: Int = 50 { didSet { persist(historyLimit, .historyLimit) } }

    // MARK: - Updates

    @Published public var automaticUpdateChecks: Bool = true { didSet { persist(automaticUpdateChecks, .automaticUpdateChecks) } }
    /// Whether pre-releases count as updates. Off, so a published beta never nags a stable install.
    @Published public var includePrereleaseUpdates: Bool = false { didSet { persist(includePrereleaseUpdates, .includePrereleaseUpdates) } }
    /// Unix time of the last check GitHub actually answered. 0 means never.
    @Published public var lastUpdateCheck: Double = 0 { didSet { persist(lastUpdateCheck, .lastUpdateCheck) } }
    /// The one version "Skip This Version" was pressed on. Later versions are still offered.
    @Published public var skippedUpdateVersion: String = "" { didSet { persist(skippedUpdateVersion, .skippedUpdateVersion) } }

    // MARK: - Init

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        load()
        loading = false
    }

    public static var defaultSaveDirectory: URL {
        FileManager.default.urls(for: .desktopDirectory, in: .userDomainMask).first
            ?? FileManager.default.homeDirectoryForCurrentUser
    }

    public var saveDirectory: URL { URL(fileURLWithPath: saveDirectoryPath) }

    // MARK: - Persistence

    private enum Key: String {
        case showMenuBarIcon
        case showPreview, previewCorner, previewDuration, previewSize, playCaptureSound, showHUD, launchAtLogin
        case hasCompletedSetup
        case saveDirectoryPath, autoSaveToDisk, filenameTemplate, imageFormat, includeCursor
        case includeWindowShadow, captureDelay, autoCopyToClipboard
        case lineBreakMode, dehyphenate, collapseWhitespace, recognitionLevel, automaticLanguageDetection
        case recognitionLanguages, usesLanguageCorrection, customWords, enhanceSmallSelections
        case autoCopyOCR, showOCRReview, keepOCRImage
        case quickActionActivation, releaseOnAppSwitch
        case historyEnabled, historyLimit
        case automaticUpdateChecks, includePrereleaseUpdates, lastUpdateCheck, skippedUpdateVersion
        case lastMarkupTool, lastMarkupShape
    }

    private func persist(_ value: Any, _ key: Key) {
        guard !loading else { return }
        defaults.set(value, forKey: key.rawValue)
    }

    private func load() {
        func bool(_ k: Key, _ fallback: Bool) -> Bool {
            defaults.object(forKey: k.rawValue) as? Bool ?? fallback
        }
        func double(_ k: Key, _ fallback: Double) -> Double {
            defaults.object(forKey: k.rawValue) as? Double ?? fallback
        }
        func int(_ k: Key, _ fallback: Int) -> Int {
            defaults.object(forKey: k.rawValue) as? Int ?? fallback
        }
        func string(_ k: Key, _ fallback: String) -> String {
            defaults.object(forKey: k.rawValue) as? String ?? fallback
        }
        func strings(_ k: Key, _ fallback: [String]) -> [String] {
            defaults.object(forKey: k.rawValue) as? [String] ?? fallback
        }

        showMenuBarIcon = bool(.showMenuBarIcon, true)
        showPreview = bool(.showPreview, true)
        previewCorner = PreviewCorner(rawValue: string(.previewCorner, "")) ?? .bottomRight
        previewDuration = double(.previewDuration, 5)
        previewSize = double(.previewSize, 220)
        playCaptureSound = bool(.playCaptureSound, true)
        showHUD = bool(.showHUD, true)
        launchAtLogin = bool(.launchAtLogin, false)
        hasCompletedSetup = bool(.hasCompletedSetup, false)

        saveDirectoryPath = string(.saveDirectoryPath, Self.defaultSaveDirectory.path)
        autoSaveToDisk = bool(.autoSaveToDisk, false)
        filenameTemplate = string(.filenameTemplate, "Screenshot {date} at {time}")
        imageFormat = ImageFormat(rawValue: string(.imageFormat, "")) ?? .png
        includeCursor = bool(.includeCursor, false)
        includeWindowShadow = bool(.includeWindowShadow, true)
        captureDelay = int(.captureDelay, 0)
        autoCopyToClipboard = bool(.autoCopyToClipboard, false)

        lineBreakMode = LineBreakMode(rawValue: string(.lineBreakMode, "")) ?? .smartParagraphs
        dehyphenate = bool(.dehyphenate, true)
        collapseWhitespace = bool(.collapseWhitespace, true)
        recognitionLevel = RecognitionLevelSetting(rawValue: string(.recognitionLevel, "")) ?? .accurate
        automaticLanguageDetection = bool(.automaticLanguageDetection, true)
        recognitionLanguages = strings(.recognitionLanguages, ["en-US"])
        usesLanguageCorrection = bool(.usesLanguageCorrection, true)
        customWords = strings(.customWords, [])
        enhanceSmallSelections = bool(.enhanceSmallSelections, true)
        autoCopyOCR = bool(.autoCopyOCR, true)
        showOCRReview = bool(.showOCRReview, false)
        keepOCRImage = bool(.keepOCRImage, false)

        quickActionActivation = QuickActionActivation(rawValue: string(.quickActionActivation, "")) ?? .global
        releaseOnAppSwitch = bool(.releaseOnAppSwitch, true)

        lastMarkupTool = string(.lastMarkupTool, MarkupTool.arrow.rawValue)
        lastMarkupShape = string(.lastMarkupShape, MarkupTool.arrow.rawValue)
        historyEnabled = bool(.historyEnabled, true)
        historyLimit = int(.historyLimit, 50)

        automaticUpdateChecks = bool(.automaticUpdateChecks, true)
        includePrereleaseUpdates = bool(.includePrereleaseUpdates, false)
        lastUpdateCheck = double(.lastUpdateCheck, 0)
        skippedUpdateVersion = string(.skippedUpdateVersion, "")
    }
}
