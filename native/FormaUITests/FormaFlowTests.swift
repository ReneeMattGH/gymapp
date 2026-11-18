import XCTest

final class FormaFlowTests: XCTestCase {
    private var app: XCUIApplication!

    override func setUpWithError() throws {
        continueAfterFailure = false
        app = XCUIApplication()
        app.launch()
    }

    func testPreviewOnboardingWorkoutAndTabs() throws {
        XCTAssertTrue(app.staticTexts["SETUP REQUIRED"].waitForExistence(timeout: 20))
        snap("01-setup-required")

        let previewButton = app.buttons["Explore preview data"]
        scrollUntilHittable(previewButton)
        previewButton.tap()

        let explore = app.alerts.buttons["Explore"]
        XCTAssertTrue(explore.waitForExistence(timeout: 5))
        explore.tap()

        let nameField = app.textFields["What should we call you?"]
        XCTAssertTrue(nameField.waitForExistence(timeout: 15), "Onboarding did not appear")
        nameField.tap()
        nameField.typeText("Matt")
        snap("02-onboarding-about")

        tapButton("Continue")
        settle()
        snap("03-onboarding-experience")
        tapButton("Continue")
        settle()
        snap("04-onboarding-direction")
        tapButton("Continue")
        settle()
        snap("05-onboarding-schedule")
        tapButton("Continue")
        settle()
        snap("06-onboarding-equipment")
        tapButton("Continue")
        settle()
        snap("07-onboarding-preferences")
        tapButton("Continue")
        settle()
        snap("08-onboarding-review")

        tapButton("Build my plan", timeout: 10)
        let springboard = XCUIApplication(bundleIdentifier: "com.apple.springboard")
        let allowNotifications = springboard.buttons["Allow"]
        if allowNotifications.waitForExistence(timeout: 10) {
            allowNotifications.tap()
        }
        let enter = app.buttons["Enter Forma"]
        XCTAssertTrue(enter.waitForExistence(timeout: 30), "Plan was not generated")
        snap("09-plan-ready")
        enter.tap()

        let homeTab = app.tabBars.buttons["Home"]
        XCTAssertTrue(homeTab.waitForExistence(timeout: 10), "Main tabs did not appear")

        let tabNames = ["Home", "Workouts", "Community", "Progress", "Profile"]
        for (index, name) in tabNames.enumerated() {
            app.tabBars.buttons[name].tap()
            sleep(1)
            snap("1\(index)-tab-\(name.lowercased())")
        }

        app.tabBars.buttons["Workouts"].tap()
        startWorkout()
        sleep(2)
        snap("20-workout-active")

        let logSet = app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "Log set")).firstMatch
        scrollUntilHittable(logSet)
        logSet.tap()
        sleep(2)
        let resting = app.staticTexts.matching(NSPredicate(format: "label CONTAINS %@", "Resting")).firstMatch
        XCTAssertTrue(resting.waitForExistence(timeout: 5), "Rest timer did not start after logging a set")
        snap("21-workout-set-logged")

        XCUIDevice.shared.press(.home)
        sleep(2)
        app.activate()
        sleep(2)
        XCTAssertTrue(app.buttons["Finish workout"].waitForExistence(timeout: 8), "Workout did not survive backgrounding")
        snap("21b-after-background")

        tapButton("Finish workout", timeout: 8)
        let confirmFinish = app.buttons["Finish & save"].firstMatch
        XCTAssertTrue(confirmFinish.waitForExistence(timeout: 5))
        confirmFinish.tap()

        let done = app.buttons["Done"]
        XCTAssertTrue(done.waitForExistence(timeout: 15), "Workout summary did not appear")
        snap("22-workout-summary")
        done.tap()

        app.tabBars.buttons["Progress"].tap()
        sleep(1)
        snap("23-progress-after-workout")

        app.tabBars.buttons["Community"].tap()
        sleep(2)
        XCTAssertTrue(
            app.staticTexts["Community is off in preview mode"].waitForExistence(timeout: 10),
            "Preview Community must honestly explain that no real members exist"
        )
        XCTAssertTrue(
            app.staticTexts["It does not create sample members, posts or messages to fill space."].exists,
            "Preview Community must state that no sample data is generated"
        )
        sleep(1)
        snap("24-community-preview")

        app.tabBars.buttons["Profile"].tap()
        sleep(1)
        let remindersRow = app.buttons.matching(NSPredicate(format: "label CONTAINS %@", "Reminders")).firstMatch
        scrollUntilHittable(remindersRow)
        remindersRow.tap()

        let saveReminders = app.buttons["Save reminders"]
        XCTAssertTrue(saveReminders.waitForExistence(timeout: 8), "Reminders screen did not open")
        scrollUntilHittable(saveReminders)
        snap("25-reminders")
        saveReminders.tap()

        let allow = springboard.buttons["Allow"]
        if allow.waitForExistence(timeout: 5) {
            allow.tap()
        }
        sleep(3)
        snap("26-reminders-result")

        app.navigationBars.buttons.firstMatch.tap()
        let healthRow = app.buttons.matching(NSPredicate(format: "label CONTAINS %@", "Apple Health")).firstMatch
        scrollUntilHittable(healthRow)
        healthRow.tap()
        XCTAssertTrue(app.staticTexts["Optional context"].waitForExistence(timeout: 8), "Health screen did not open")
        snap("27-health")

        app.navigationBars.buttons.firstMatch.tap()
        app.tabBars.buttons["Workouts"].tap()
        sleep(1)
        // Finishing a workout can leave the workout-day screen pushed on this tab.
        let workoutsBack = app.navigationBars.buttons["BackButton"]
        if workoutsBack.exists {
            workoutsBack.tap()
            sleep(1)
        }
        let libraryRow = app.buttons.matching(NSPredicate(format: "label CONTAINS %@", "Exercise library")).firstMatch
        scrollUntilHittable(libraryRow)
        libraryRow.tap()

        let searchField = app.textFields["Search exercises"]
        XCTAssertTrue(searchField.waitForExistence(timeout: 8), "Exercise library did not open")
        sleep(1)
        snap("28-library")
        searchField.tap()
        searchField.typeText("squat")
        sleep(1)
        app.swipeUp()
        let favourite = app.buttons["Add favourite"].firstMatch
        scrollUntilHittable(favourite)
        XCTAssertTrue(favourite.exists, "No exercise matched the search")
        favourite.tap()
        sleep(1)
        XCTAssertTrue(app.buttons["Remove favourite"].firstMatch.waitForExistence(timeout: 5), "Favourite did not toggle")
        snap("29-library-favourite")

        let exerciseRow = app.staticTexts["Barbell back squat"]
        scrollUntilHittable(exerciseRow)
        XCTAssertTrue(exerciseRow.exists, "No exercise matched the search")
        exerciseRow.tap()
        XCTAssertTrue(app.staticTexts["HOW TO PERFORM"].waitForExistence(timeout: 8), "Exercise detail did not open")
        sleep(1)
        snap("30-library-detail")
        app.navigationBars.buttons.firstMatch.tap()
        sleep(1)
        let libraryBack = app.navigationBars.buttons["BackButton"]
        if libraryBack.exists {
            libraryBack.tap()
            sleep(1)
        }

        let formCard = app.buttons.matching(NSPredicate(format: "label CONTAINS %@", "Camera form check")).firstMatch
        scrollUntilHittable(formCard)
        XCTAssertTrue(formCard.exists, "Camera form check entry is missing from Workouts")
        formCard.tap()

        XCTAssertTrue(app.staticTexts["Check your form"].waitForExistence(timeout: 8), "Form analysis setup did not open")
        XCTAssertTrue(
            app.staticTexts["No camera is available on this device. The Simulator cannot test camera or pose analysis."].waitForExistence(timeout: 5),
            "Simulator camera unavailability was not explained honestly"
        )
        let startAnalysis = app.buttons["Start analysis"].firstMatch
        XCTAssertTrue(startAnalysis.exists, "Start analysis button is missing")
        XCTAssertFalse(startAnalysis.isEnabled, "Start analysis must be disabled when no camera exists")
        snap("33-form-analysis-setup")

        app.buttons["Close form analysis"].tap()
        sleep(1)

        app.terminate()
        app.launch()
        XCTAssertTrue(app.tabBars.buttons["Home"].waitForExistence(timeout: 20), "Profile and plan did not persist across relaunch")
        snap("31-relaunch-home")

        app.tabBars.buttons["Progress"].tap()
        sleep(1)
        XCTAssertFalse(app.staticTexts["Finish a session to start the chart."].exists, "Saved session is missing from progress charts")
        snap("32-relaunch-progress")
    }

    private func startWorkout() {
        let today = app.buttons["Start today's session"]
        if today.waitForExistence(timeout: 5), today.isHittable {
            today.tap()
            return
        }
        let dayRow = app.buttons.matching(NSPredicate(format: "label CONTAINS %@", "exercises ·")).firstMatch
        scrollUntilHittable(dayRow)
        XCTAssertTrue(dayRow.exists, "No training day was available to open")
        dayRow.tap()
        tapButton("Start workout")
    }

    private func tapButton(_ label: String, timeout: TimeInterval = 8) {
        let button = app.buttons[label].firstMatch
        if !button.waitForExistence(timeout: timeout) {
            scrollUntilHittable(button)
        } else if !button.isHittable {
            scrollUntilHittable(button)
        }
        XCTAssertTrue(button.exists && button.isHittable, "Button \(label) was not tappable")
        button.tap()
    }

    private func settle() {
        sleep(1)
    }

    private func scrollUntilHittable(_ element: XCUIElement, maxSwipes: Int = 8) {
        var swipes = 0
        while !(element.exists && element.isHittable) && swipes < maxSwipes {
            app.swipeUp()
            swipes += 1
        }
    }

    private func snap(_ name: String) {
        let attachment = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
