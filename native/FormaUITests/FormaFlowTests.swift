import XCTest

final class FormaFlowTests: XCTestCase {
    private var app: XCUIApplication!

    override func setUpWithError() throws {
        continueAfterFailure = false
        app = XCUIApplication()
        app.launch()
    }

    func testLocalProfileOnboardingWorkoutAndTabs() throws {
        let nameField = app.textFields["What should we call you?"]
        XCTAssertTrue(nameField.waitForExistence(timeout: 25), "Onboarding did not appear on a fresh install")
        snap("01-onboarding-about")
        nameField.tap()
        nameField.typeText("Matt")

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
        let communityUnavailable = app.staticTexts.matching(
            NSPredicate(format: "label IN %@", ["Sign in to join the community", "Community needs the Forma backend"])
        ).firstMatch
        XCTAssertTrue(
            communityUnavailable.waitForExistence(timeout: 10),
            "Community must honestly explain why it is unavailable while signed out"
        )
        XCTAssertTrue(
            app.staticTexts["It does not create sample members, posts or messages to fill space."].exists,
            "Community must state that no sample data is generated"
        )
        sleep(1)
        snap("24-community-unavailable")

        app.tabBars.buttons["Profile"].tap()
        sleep(1)
        XCTAssertTrue(
            app.staticTexts["PROFILES"].waitForExistence(timeout: 8),
            "Local profiles section is missing"
        )
        XCTAssertTrue(
            app.staticTexts["Stored on this device"].exists,
            "Profile header must say data is stored on this device"
        )
        snap("24b-local-profiles")

        verifyAccountScreen()

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

    /// Opens the remote Account screen. With the dev backend at
    /// http://localhost:8787 running, it also creates and deletes a real
    /// account through the UI; without it, it only checks the signed-out form.
    private func verifyAccountScreen() {
        let accountRow = app.buttons.matching(NSPredicate(format: "label CONTAINS %@", "Connect account")).firstMatch
        scrollUntilHittable(accountRow)
        XCTAssertTrue(accountRow.exists, "The Forma account row is missing from Profile")
        accountRow.tap()

        XCTAssertTrue(app.staticTexts["Forma account."].waitForExistence(timeout: 8), "Account screen did not open")
        snap("24c-account-signed-out")
        XCTAssertTrue(app.buttons["Create account"].firstMatch.exists, "Create account option is missing")

        guard backendIsReachable() else {
            print("Backend not reachable at localhost:8787; the account form was not submitted.")
            app.navigationBars.buttons.firstMatch.tap()
            return
        }

        let suffix = String(UUID().uuidString.prefix(8)).lowercased()
        let email = "uitest-\(suffix)@example.com"
        let password = "forma-uitest-\(suffix)"

        app.buttons["Create account"].firstMatch.tap()
        let nameField = app.textFields["How members see you"]
        XCTAssertTrue(nameField.waitForExistence(timeout: 5))
        nameField.tap()
        nameField.typeText("UI Tester")

        let emailField = app.textFields["you@example.com"]
        emailField.tap()
        emailField.typeText(email)

        let passwordField = app.secureTextFields["At least 10 characters"]
        passwordField.tap()
        passwordField.typeText(password)

        let submit = app.buttons.matching(NSPredicate(format: "label == %@", "Create account")).allElementsBoundByIndex.last
        XCTAssertNotNil(submit, "Create account submit button is missing")
        submit?.tap()

        XCTAssertTrue(app.staticTexts["UNVERIFIED"].waitForExistence(timeout: 15), "A real registration did not produce a signed-in account: \(email)")
        XCTAssertTrue(app.staticTexts[email].exists, "The signed-in account email is missing")
        snap("24d-account-signed-in")

        let signOut = app.buttons["Sign out"]
        scrollUntilHittable(signOut)
        signOut.tap()
        XCTAssertTrue(app.buttons["Sign in"].firstMatch.waitForExistence(timeout: 10), "Signing out did not return to the signed-out form")
        app.swipeDown()
        app.swipeDown()

        let signInChip = app.buttons["Sign in"].firstMatch
        XCTAssertTrue(signInChip.waitForExistence(timeout: 5))
        signInChip.tap()

        let signInEmail = app.textFields["you@example.com"]
        XCTAssertTrue(signInEmail.waitForExistence(timeout: 5))
        XCTAssertEqual(signInEmail.value as? String, email, "The email field should still hold the account address after signing out")
        let signInPassword = app.secureTextFields["Your password"]
        signInPassword.tap()
        signInPassword.typeText(password)
        let signIn = app.buttons.matching(NSPredicate(format: "label == %@", "Sign in")).allElementsBoundByIndex.last
        XCTAssertNotNil(signIn, "Sign in submit button is missing")
        signIn?.tap()
        XCTAssertTrue(app.staticTexts["UNVERIFIED"].waitForExistence(timeout: 15), "Signing back in with the real password failed: \(email)")
        snap("24e-account-signed-in-again")

        verifyLiveCommunity()

        let deleteButton = app.buttons["Delete account"]
        scrollUntilHittable(deleteButton)
        deleteButton.tap()
        let deletePassword = app.secureTextFields["Account password"]
        XCTAssertTrue(deletePassword.waitForExistence(timeout: 5))
        deletePassword.tap()
        deletePassword.typeText(password)
        let confirmDelete = app.buttons["Delete account permanently"]
        scrollUntilHittable(confirmDelete)
        confirmDelete.tap()

        XCTAssertTrue(app.buttons["Sign in"].firstMatch.waitForExistence(timeout: 15), "Deleting the account did not return to the signed-out form")
        snap("24f-account-deleted")

        app.tabBars.buttons["Community"].tap()
        XCTAssertTrue(
            app.staticTexts["Sign in to join the community"].waitForExistence(timeout: 15),
            "Community should return to the signed-out notice after the account is deleted"
        )
        snap("24g-community-signed-out")
        app.tabBars.buttons["Profile"].tap()
        sleep(1)

        app.navigationBars.buttons.firstMatch.tap()
        sleep(1)
    }

    /// With a real signed-in account, Community must render the live bootstrap
    /// from the backend instead of the unavailable notice.
    private func verifyLiveCommunity() {
        app.tabBars.buttons["Community"].tap()
        XCTAssertTrue(
            app.staticTexts["Train together."].waitForExistence(timeout: 20),
            "Signed-in Community did not load from the backend"
        )
        XCTAssertTrue(
            app.staticTexts["Create your community profile"].waitForExistence(timeout: 10),
            "A new account should be asked to create a community profile"
        )
        let placeCard = app.staticTexts.matching(
            NSPredicate(format: "label IN %@", ["No gym or area yet", "Area-only selection. No gym chosen."])
        ).firstMatch
        XCTAssertTrue(placeCard.waitForExistence(timeout: 10), "Community must show the member's gym or area selection")
        XCTAssertTrue(
            app.staticTexts.matching(NSPredicate(format: "label CONTAINS[c] %@", "at your gym")).firstMatch.exists,
            "Community statistics are missing"
        )
        sleep(1)
        snap("24e2-community-live")

        app.buttons["Set up profile"].firstMatch.tap()
        XCTAssertTrue(
            app.navigationBars["Create profile"].waitForExistence(timeout: 8),
            "Community profile editor did not open"
        )
        snap("24e3-community-profile-editor")
        app.navigationBars.buttons.firstMatch.tap()
        sleep(1)

        app.tabBars.buttons["Profile"].tap()
        sleep(1)
    }

    private func backendIsReachable() -> Bool {
        guard let url = URL(string: "http://localhost:8787/health") else { return false }
        var request = URLRequest(url: url)
        request.timeoutInterval = 3
        var reachable = false
        let semaphore = DispatchSemaphore(value: 0)
        URLSession.shared.dataTask(with: request) { _, response, _ in
            reachable = (response as? HTTPURLResponse)?.statusCode == 200
            semaphore.signal()
        }.resume()
        _ = semaphore.wait(timeout: .now() + 5)
        return reachable
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
