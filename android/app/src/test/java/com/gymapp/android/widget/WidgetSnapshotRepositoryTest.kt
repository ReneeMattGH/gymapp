package com.gymapp.android.widget

import android.content.Context
import androidx.room.Room
import androidx.test.core.app.ApplicationProvider
import com.gymapp.android.data.LocalRepository
import com.gymapp.android.data.local.FormaDatabase
import com.gymapp.android.domain.SessionStatus
import com.gymapp.android.widget.WidgetFixtures.epoch
import com.gymapp.android.widget.WidgetFixtures.session
import com.gymapp.android.widget.WidgetFixtures.today
import com.gymapp.android.widget.WidgetFixtures.weekPlan
import com.gymapp.android.widget.WidgetFixtures.zone
import kotlinx.coroutines.runBlocking
import org.junit.After
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Before
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.annotation.Config

@RunWith(RobolectricTestRunner::class)
@Config(sdk = [34])
class WidgetSnapshotRepositoryTest {
    private lateinit var database: FormaDatabase
    private lateinit var repository: LocalRepository

    @Before
    fun setUp() {
        val context: Context = ApplicationProvider.getApplicationContext()
        database = Room.inMemoryDatabaseBuilder(context, FormaDatabase::class.java)
            .allowMainThreadQueries()
            .build()
        repository = LocalRepository(database)
    }

    @After
    fun tearDown() {
        database.close()
    }

    @Test
    fun `no active profile produces the neutral empty snapshot`() = runBlocking {
        val snapshot = WidgetSnapshotRepository(database, zone).load(epoch(today))

        assertFalse(snapshot.hasPlan)
        assertEquals(WidgetTodayState.NO_PLAN, snapshot.today.state)
        assertEquals("", snapshot.accountId)
        assertEquals(7, snapshot.week.days.size)
    }

    @Test
    fun `active profile with a plan and session renders from Room`() = runBlocking {
        val plan = weekPlan(1, 3, 5)
        repository.savePlan(plan)
        repository.savePreferences(
            com.gymapp.android.domain.Preferences(userId = WidgetFixtures.USER_ID, workoutDays = listOf(1, 3, 5)),
        )
        repository.saveSession(session(today))
        repository.setActiveProfileId(WidgetFixtures.USER_ID)

        val snapshot = WidgetSnapshotRepository(database, zone).load(epoch(today))

        assertEquals(WidgetFixtures.USER_ID, snapshot.accountId)
        assertTrue(snapshot.hasPlan)
        assertEquals(WidgetTodayState.COMPLETED, snapshot.today.state)
        assertEquals("Upper body", snapshot.today.completedTitle)
        assertEquals(1, snapshot.week.completed)
        assertEquals(3, snapshot.week.goal)
        assertEquals(1, snapshot.totalCompleted)
        assertEquals(1, snapshot.streak)
    }

    @Test
    fun `an open workout is reported as in progress even before it is saved as a session`() = runBlocking {
        repository.savePlan(weekPlan(1, 3, 5))
        repository.setActiveProfileId(WidgetFixtures.USER_ID)
        repository.saveActiveWorkout(
            com.gymapp.android.domain.ActiveWorkout(
                sessionId = "active-1",
                userId = WidgetFixtures.USER_ID,
                planDayId = "day-3",
                planId = WidgetFixtures.PLAN_ID,
                title = "Push day",
                startedAt = epoch(today) - 300_000L,
                status = com.gymapp.android.domain.WorkoutRunStatus.ACTIVE,
            ),
        )

        val snapshot = WidgetSnapshotRepository(database, zone).load(epoch(today))

        assertEquals(WidgetTodayState.IN_PROGRESS, snapshot.today.state)
        assertEquals("Push day", snapshot.today.activeSessionTitle)
        assertEquals(0, snapshot.week.completed)
    }

    @Test
    fun `abandoned sessions never count as completed`() = runBlocking {
        repository.savePlan(weekPlan(1, 3, 5))
        repository.setActiveProfileId(WidgetFixtures.USER_ID)
        repository.saveSession(session(today).copy(status = SessionStatus.ABANDONED))

        val snapshot = WidgetSnapshotRepository(database, zone).load(epoch(today))

        assertEquals(0, snapshot.totalCompleted)
        assertEquals(WidgetTodayState.WORKOUT, snapshot.today.state)
        assertEquals(0, snapshot.streak)
    }
}
