import pool from '../db.js';
import { CronJob } from 'cron';
import console from 'console';

// Note: Firebase Admin SDK initialization should be done in server.js
// This is a placeholder that works without it - in production,
// replace messaging.send() with actual Firebase calls

const messaging = {
  send: async (message) => {
    console.log('[Scheduler] Would send notification:', message.notification.body);
    return { messageId: 'fake-id' };
  }
};

export function startAttendanceScheduler() {
  // Run every minute
  const job = new CronJob('* * * * *', async () => {
    try {
      await checkAndSendReminders();
    } catch (error) {
      console.error('[Scheduler] Error:', error.message);
    }
  });

  job.start();
  console.log('[Scheduler] Attendance reminder scheduler started');
}

async function checkAndSendReminders() {
  const now = new Date();
  const currentTime = `${String(now.getHours()).padStart(2, '0')}:${String(now.getMinutes()).padStart(2, '0')}:00`;
  const dayOfWeek = now.getDay(); // 0 = Sunday, 6 = Saturday

  // Skip weekends
  if (dayOfWeek === 0 || dayOfWeek === 6) {
    return;
  }

  // Get all enabled teams
  const { rows: teams } = await pool.query(
    'SELECT * FROM attendance_config WHERE enabled = true'
  );

  for (const team of teams) {
    // Check check-in reminders
    await checkCheckInReminders(team, currentTime);

    // Check check-out reminders
    await checkCheckOutReminders(team, currentTime);

    // Check for auto-checkout
    await checkAutoCheckout(team, currentTime);
  }
}

async function checkCheckInReminders(team, currentTime) {
  const startTime = team.checkin_start_time;
  const endTime = team.checkin_deadline_time;
  const interval = team.checkin_reminder_interval_minutes;

  // Check if current time is within reminder window
  if (currentTime < startTime || currentTime >= team.checkin_deadline_time) {
    return;
  }

  // Calculate if this minute should have a reminder
  const [startHour, startMin] = startTime.split(':').map(Number);
  const [currentHour, currentMin] = currentTime.split(':').map(Number);

  const minutesSinceStart =
    (currentHour - startHour) * 60 + (currentMin - startMin);

  if (minutesSinceStart % interval !== 0) {
    return;
  }

  // Get team members who haven't checked in
  const { rows: staffNotCheckedIn } = await pool.query(
    `SELECT e.id, e.full_name, dt.fcm_token
     FROM team_members tm
     JOIN employees e ON e.id = tm.employee_id
     JOIN device_tokens dt ON dt.employee_id = e.id
     WHERE tm.team_id = $1
       AND dt.fcm_token IS NOT NULL
       AND NOT EXISTS (
         SELECT 1 FROM attendance a
         WHERE a.employee_id = e.id
           AND DATE(a.checked_in_at) = CURRENT_DATE
       )`,
    [team.id]
  );

  // Send notifications
  for (const staff of staffNotCheckedIn) {
    const firstName = staff.full_name.split(' ')[0];
    const message = {
      notification: {
        title: 'Attendance Reminder',
        body: `Hi ${firstName}, please mark your attendance`,
      },
      data: {
        type: 'attendance_checkin_reminder',
        timestamp: new Date().toISOString(),
      },
      token: staff.fcm_token,
    };

    try {
      await messaging.send(message);
      console.log(`[Scheduler] Sent check-in reminder to ${staff.full_name}`);
    } catch (error) {
      console.error(
        `[Scheduler] Failed to send reminder to ${staff.full_name}:`,
        error.message
      );
    }
  }
}

async function checkCheckOutReminders(team, currentTime) {
  const startTime = team.checkout_start_time;
  const deadline = team.checkout_autocheckin_time;
  const interval = team.checkout_reminder_interval_minutes;

  // Check if current time is within reminder window
  if (currentTime < startTime || currentTime >= deadline) {
    return;
  }

  // Calculate if this minute should have a reminder
  const [startHour, startMin] = startTime.split(':').map(Number);
  const [currentHour, currentMin] = currentTime.split(':').map(Number);

  const minutesSinceStart =
    (currentHour - startHour) * 60 + (currentMin - startMin);

  if (minutesSinceStart % interval !== 0) {
    return;
  }

  // Get team members who haven't checked out
  const { rows: staffNotCheckedOut } = await pool.query(
    `SELECT e.id, e.full_name, dt.fcm_token
     FROM team_members tm
     JOIN employees e ON e.id = tm.employee_id
     JOIN device_tokens dt ON dt.employee_id = e.id
     WHERE tm.team_id = $1
       AND dt.fcm_token IS NOT NULL
       AND EXISTS (
         SELECT 1 FROM attendance a
         WHERE a.employee_id = e.id
           AND DATE(a.checked_in_at) = CURRENT_DATE
           AND a.checked_out_at IS NULL
       )`,
    [team.id]
  );

  // Send notifications
  for (const staff of staffNotCheckedOut) {
    const firstName = staff.full_name.split(' ')[0];
    const message = {
      notification: {
        title: 'Checkout Reminder',
        body: `${firstName}, please mark your checkout`,
      },
      data: {
        type: 'attendance_checkout_reminder',
        timestamp: new Date().toISOString(),
      },
      token: staff.fcm_token,
    };

    try {
      await messaging.send(message);
      console.log(`[Scheduler] Sent check-out reminder to ${staff.full_name}`);
    } catch (error) {
      console.error(
        `[Scheduler] Failed to send reminder to ${staff.full_name}:`,
        error.message
      );
    }
  }
}

async function checkAutoCheckout(team, currentTime) {
  const autoCheckoutTime = team.checkout_autocheckin_time;

  // Exact minute match for auto-checkout
  if (currentTime !== autoCheckoutTime) {
    return;
  }

  // Find staff who should be auto-checked-out
  const { rows: staffToAutoCheckout } = await pool.query(
    `SELECT e.id, e.full_name, a.id as attendance_id
     FROM team_members tm
     JOIN employees e ON e.id = tm.employee_id
     WHERE tm.team_id = $1
       AND EXISTS (
         SELECT 1 FROM attendance a
         WHERE a.employee_id = e.id
           AND DATE(a.checked_in_at) = CURRENT_DATE
           AND a.checked_out_at IS NULL
       )`,
    [team.id]
  );

  for (const staff of staffToAutoCheckout) {
    // Update attendance record
    await pool.query(
      `UPDATE attendance
       SET checked_out_at = NOW(), is_auto_checkout = true
       WHERE employee_id = $1
         AND DATE(checked_in_at) = CURRENT_DATE
         AND checked_out_at IS NULL`,
      [staff.id]
    );

    console.log(`[Scheduler] Auto-checked out ${staff.full_name}`);

    // Send notification
    const firstName = staff.full_name.split(' ')[0];
    const { rows: tokens } = await pool.query(
      'SELECT fcm_token FROM device_tokens WHERE employee_id = $1',
      [staff.id]
    );

    for (const { fcm_token } of tokens) {
      if (fcm_token) {
        const message = {
          notification: {
            title: 'Auto Checked Out',
            body: `${firstName}, auto checked out at ${autoCheckoutTime}`,
          },
          data: {
            type: 'attendance_auto_checkout',
            timestamp: new Date().toISOString(),
          },
          token: fcm_token,
        };

        try {
          await messaging.send(message);
        } catch (error) {
          console.error(`Failed to send auto-checkout notification:`, error.message);
        }
      }
    }
  }
}
