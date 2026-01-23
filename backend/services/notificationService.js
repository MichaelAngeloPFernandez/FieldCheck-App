const twilio = require('twilio');

let twilioClient;

function getTwilioClient() {
  if (twilioClient) return twilioClient;
  const sid = process.env.TWILIO_ACCOUNT_SID;
  const token = process.env.TWILIO_AUTH_TOKEN;
  if (!sid || !token) {
    return null;
  }
  twilioClient = twilio(sid, token);
  return twilioClient;
}

async function sendSms(to, body) {
  const from = process.env.TWILIO_FROM_NUMBER;
  const client = getTwilioClient();

  if (!client || !from || !to || !body) {
    if (process.env.NODE_ENV !== 'production') {
      console.log('[SMS] Skipped - missing configuration or parameters', {
        hasClient: !!client,
        from,
        to,
      });
    }
    return;
  }

  try {
    await client.messages.create({ from, to, body });
  } catch (e) {
    console.error('[SMS] Failed to send', e.message || e);
  }
}

function formatTaskLabel(task) {
  const parts = [task.title];
  if (task.dueDate) {
    try {
      const d = new Date(task.dueDate);
      parts.push(`Due: ${d.toLocaleString()}`);
    } catch (_) {}
  }
  return parts.join(' • ');
}

async function notifyTaskAssigned(user, task) {
  if (!user || !user.phone) return;
  const label = formatTaskLabel(task);
  const body = `New task assigned to you: ${label}`;
  await sendSms(user.phone, body);
}

async function notifyTaskOverdue(user, task) {
  if (!user || !user.phone) return;
  const label = formatTaskLabel(task);
  const body = `Task overdue: ${label}. Please review and update status.`;
  await sendSms(user.phone, body);
}

async function notifyTaskEscalated(user, task) {
  if (!user || !user.phone) return;
  const label = formatTaskLabel(task);
  const body = `Task escalated: ${label}. Please address immediately.`;
  await sendSms(user.phone, body);
}

async function notifyAttendanceCheckIn(user, geofence) {
  if (!user || !user.phone) return;
  const geofenceName = geofence?.name ? ` at ${geofence.name}` : '';
  const body = `Attendance update: you checked in${geofenceName}.`;
  await sendSms(user.phone, body);
}

async function notifyAttendanceCheckOut(user, geofence) {
  if (!user || !user.phone) return;
  const geofenceName = geofence?.name ? ` from ${geofence.name}` : '';
  const body = `Attendance update: you checked out${geofenceName}.`;
  await sendSms(user.phone, body);
}

async function notifyAutoCheckoutWarning(user, minutesRemaining, geofenceName) {
  if (!user || !user.phone) return;
  if (Number.isFinite(minutesRemaining)) {
    const plural = minutesRemaining === 1 ? '' : 's';
    const geofenceLabel = geofenceName ? ` at ${geofenceName}` : '';
    const body = `Auto-checkout warning: you will be checked out in ${minutesRemaining} minute${plural} if you remain offline${geofenceLabel}.`;
    await sendSms(user.phone, body);
    return;
  }

  const geofenceLabel = geofenceName ? ` at ${geofenceName}` : '';
  const body = `Auto-checkout notice: your previous session was auto-closed${geofenceLabel}.`;
  await sendSms(user.phone, body);
}

async function notifyLocationWarning(user, reason) {
  if (!user || !user.phone) return;
  const body = `Location Verification Failed: ${reason || 'Unknown reason'}. Please verify your GPS is enabled.`;
  await sendSms(user.phone, body);
}

async function notifyWorkloadWarning(user, activeTaskCount, maxActive) {
  if (!user || !user.phone) return;
  const limitLabel = Number.isFinite(maxActive) ? `/${maxActive}` : '';
  const body = `Workload Alert: You have ${activeTaskCount}${limitLabel} active tasks. Consider completing some or requesting help.`;
  await sendSms(user.phone, body);
}

module.exports = {
  sendSms,
  notifyTaskAssigned,
  notifyTaskOverdue,
  notifyTaskEscalated,
  notifyAttendanceCheckIn,
  notifyAttendanceCheckOut,
  notifyAutoCheckoutWarning,
  notifyLocationWarning,
  notifyWorkloadWarning,
};
