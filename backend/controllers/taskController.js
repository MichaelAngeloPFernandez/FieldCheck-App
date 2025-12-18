const asyncHandler = require('express-async-handler');
const Task = require('../models/Task');
const UserTask = require('../models/UserTask');
const User = require('../models/User');
const { io } = require('../server');
const Report = require('../models/Report');
const Settings = require('../models/Settings');
const notificationService = require('../services/notificationService');

async function getMaxActiveTasksPerEmployee() {
  const DEFAULT_MAX = 10;
  try {
    const doc = await Settings.findOne({ key: 'task.maxActivePerEmployee' });
    if (!doc) return DEFAULT_MAX;
    const value = doc.value;
    if (typeof value === 'number' && Number.isFinite(value) && value > 0) {
      return value;
    }
    if (value && typeof value === 'object') {
      const num = value.maxActivePerEmployee;
      if (typeof num === 'number' && Number.isFinite(num) && num > 0) {
        return num;
      }
    }
    return DEFAULT_MAX;
  } catch (_) {
    return DEFAULT_MAX;
  }
}

// --- Task status helpers ----------------------------------------------------

const TERMINAL_TASK_STATUSES = ['completed', 'reviewed', 'closed'];

function normalizeTaskStatus(status) {
  if (!status) return 'pending';
  return String(status).toLowerCase();
}

function isTerminalTaskStatus(status) {
  return TERMINAL_TASK_STATUSES.includes(normalizeTaskStatus(status));
}

function canTransitionTaskStatus(fromStatus, toStatus) {
  const from = normalizeTaskStatus(fromStatus);
  const to = normalizeTaskStatus(toStatus);

  if (from === to) return true;

  // Prevent going back from any terminal/done state to an active state
  if (isTerminalTaskStatus(from) && !isTerminalTaskStatus(to)) {
    return false;
  }

  // Otherwise allow the transition for now (future phases can tighten rules)
  return true;
}

function recalculateChecklistProgress(taskDoc) {
  if (!Array.isArray(taskDoc.checklist) || taskDoc.checklist.length === 0) {
    return;
  }

  const total = taskDoc.checklist.length;
  const completed = taskDoc.checklist.filter((item) => item && item.isCompleted).length;
  if (!total) {
    return;
  }

  const percent = Math.round((completed / total) * 100);
  if (!Number.isNaN(percent)) {
    taskDoc.progressPercent = Math.max(0, Math.min(100, percent));
  }
}

// Map Task mongoose doc to Flutter-friendly shape
function toTaskJson(doc, userTaskId) {
  const now = new Date();
  const isOverdue =
    !!doc.dueDate &&
    doc.dueDate < now &&
    normalizeTaskStatus(doc.status) !== 'completed' &&
    !doc.isArchived;

  const rawStatus = normalizeTaskStatus(doc.status);

  // Map rich lifecycle statuses into the legacy 3-state UI model
  // so existing Flutter UI (pending / in_progress / completed) keeps working.
  let uiStatus = rawStatus || 'pending';
  if (['created', 'assigned', 'accepted'].includes(rawStatus)) {
    uiStatus = 'pending';
  } else if (['blocked', 'in_progress'].includes(rawStatus)) {
    uiStatus = 'in_progress';
  } else if (['completed', 'reviewed', 'closed'].includes(rawStatus)) {
    uiStatus = 'completed';
  }

  // Keep progressPercent in sync with checklist completion when a checklist exists
  recalculateChecklistProgress(doc);

  const progressPercent =
    typeof doc.progressPercent === 'number'
      ? Math.max(0, Math.min(100, doc.progressPercent))
      : 0;

  return {
    id: doc._id.toString(),
    title: doc.title,
    description: doc.description || '',
    dueDate: doc.dueDate ? doc.dueDate.toISOString() : new Date().toISOString(),
    assignedBy: doc.assignedBy?.toString() || '',
    createdAt: doc.createdAt?.toISOString() || new Date().toISOString(),
    status: uiStatus,
    userTaskId: userTaskId || undefined,
    geofenceId: doc.geofenceId?.toString() || undefined,
    latitude: doc.latitude,
    longitude: doc.longitude,
    type: doc.type || 'general',
    difficulty: doc.difficulty || 'medium',
    isArchived: !!doc.isArchived,
    isOverdue,
    // Expose richer fields for future UI without breaking current clients
    rawStatus,
    progressPercent,
    checklist: Array.isArray(doc.checklist)
      ? doc.checklist.map((item) => ({
          label: item.label,
          isCompleted: !!item.isCompleted,
          completedAt: item.completedAt ? item.completedAt.toISOString() : null,
        }))
      : [],
    attachments: doc.attachments || {
      images: [],
      documents: [],
      others: [],
    },
    blockReason: doc.blockReason || '',
  };
}

// @route GET /api/tasks/:id
// @access Private
const getTask = asyncHandler(async (req, res) => {
  const { id } = req.params;
  const task = await Task.findById(id);
  if (!task) {
    res.status(404);
    throw new Error('Task not found');
  }
  res.json(toTaskJson(task));
});

// @route GET /api/tasks
// @access Private (admin or employee)
// Optional query: archived=true|false (default false)
const getTasks = asyncHandler(async (req, res) => {
  const { archived } = req.query;

  const filter = {};
  if (archived === 'true') {
    filter.isArchived = true;
  } else if (archived === 'false' || archived === undefined) {
    // Default to current (non-archived) tasks when not specified
    filter.isArchived = { $ne: true };
  }

  const tasks = await Task.find(filter).sort({ createdAt: -1 });
  res.json(tasks.map((t) => toTaskJson(t)));
});

// @route GET /api/tasks/current
// @access Private/Admin
const getCurrentTasks = asyncHandler(async (req, res) => {
  const tasks = await Task.find({ isArchived: { $ne: true } }).sort({ createdAt: -1 });
  res.json(tasks.map((t) => toTaskJson(t)));
});

// @route GET /api/tasks/archived
// @access Private/Admin
const getArchivedTasks = asyncHandler(async (req, res) => {
  const tasks = await Task.find({ isArchived: true }).sort({ createdAt: -1 });
  res.json(tasks.map((t) => toTaskJson(t)));
});

// @route POST /api/tasks
// @access Private/Admin
const createTask = asyncHandler(async (req, res) => {
  const { title, description, dueDate, status, geofenceId, type, difficulty } = req.body;

  if (!title) {
    res.status(400);
    throw new Error('Title is required');
  }
  if (typeof title === 'string' && title.length > 200) {
    res.status(400);
    throw new Error('Title is too long (max 200 characters)');
  }
  if (description && typeof description === 'string' && description.length > 5000) {
    res.status(400);
    throw new Error('Description is too long (max 5000 characters)');
  }
  const taskData = {
    title,
    description: description || '',
    dueDate: dueDate ? new Date(dueDate) : undefined,
    assignedBy: req.user._id,
    status: status || 'pending',
    geofenceId: geofenceId || undefined,
    type: type || 'general',
    difficulty: difficulty || 'medium',
  };
  const task = await Task.create(taskData);
  io.emit('newTask', toTaskJson(task)); // Emit real-time event
  
  // Emit admin notification for new task
  io.emit('adminNotification', {
    type: 'task',
    action: 'created',
    taskId: task._id,
    taskTitle: task.title,
    createdBy: req.user.name,
    timestamp: new Date(),
    message: `New task: "${task.title}" created by ${req.user.name}`,
    severity: 'info',
  });
  
  res.status(201).json(toTaskJson(task));
});

// @route PUT /api/tasks/:id
// @access Private/Admin
const updateTask = asyncHandler(async (req, res) => {
  const { id } = req.params;
  const task = await Task.findById(id);
  if (!task) {
    res.status(404);
    throw new Error('Task not found');
  }
  if (req.body.title && typeof req.body.title === 'string' && req.body.title.length > 200) {
    res.status(400);
    throw new Error('Title is too long (max 200 characters)');
  }
  if (req.body.description && typeof req.body.description === 'string' && req.body.description.length > 5000) {
    res.status(400);
    throw new Error('Description is too long (max 5000 characters)');
  }
  // Only update if values are explicitly provided (not undefined)
  if (req.body.title !== undefined) task.title = req.body.title;
  if (req.body.description !== undefined) task.description = req.body.description;
  if (req.body.status !== undefined) {
    const nextStatus = req.body.status;
    if (!canTransitionTaskStatus(task.status, nextStatus)) {
      res.status(400);
      throw new Error(
        `Invalid task status transition from ${task.status || 'none'} to ${nextStatus}`,
      );
    }
    task.status = nextStatus;
  }
  if (req.body.geofenceId !== undefined) task.geofenceId = req.body.geofenceId;
  if (req.body.dueDate !== undefined) task.dueDate = new Date(req.body.dueDate);
  if (req.body.type !== undefined) task.type = req.body.type;
  if (req.body.difficulty !== undefined) task.difficulty = req.body.difficulty;
  if (req.body.progressPercent !== undefined) {
    const val = Number(req.body.progressPercent);
    if (!Number.isFinite(val) || val < 0 || val > 100) {
      res.status(400);
      throw new Error('progressPercent must be a number between 0 and 100');
    }
    task.progressPercent = Math.round(val);
  }

  const updated = await task.save();
  io.emit('updatedTask', toTaskJson(updated));
  
  // Emit admin notification for task update
  io.emit('adminNotification', {
    type: 'task',
    action: 'updated',
    taskId: updated._id,
    taskTitle: updated.title,
    updatedBy: req.user.name,
    newStatus: updated.status,
    timestamp: new Date(),
    message: `Task "${updated.title}" updated by ${req.user.name}`,
    severity: 'info',
  });
  
  res.json(toTaskJson(updated));
});

// @route DELETE /api/tasks/:id
// @access Private/Admin
const deleteTask = asyncHandler(async (req, res) => {
  const { id } = req.params;
  const task = await Task.findById(id);
  if (!task) {
    return res.status(404).json({ message: 'Task not found' });
  }
  // Also remove any user-task assignments
  await UserTask.deleteMany({ taskId: task._id });
  await task.deleteOne();
  io.emit('deletedTask', id); // Emit real-time event
  res.status(204).send();
});

// @route PUT /api/tasks/:id/archive
// @access Private/Admin
const archiveTask = asyncHandler(async (req, res) => {
  const { id } = req.params;
  const task = await Task.findById(id);
  if (!task) {
    res.status(404);
    throw new Error('Task not found');
  }
  task.isArchived = true;
  const updated = await task.save();
  io.emit('taskArchived', toTaskJson(updated));
  res.json(toTaskJson(updated));
});

// @route PUT /api/tasks/:id/restore
// @access Private/Admin
const restoreTask = asyncHandler(async (req, res) => {
  const { id } = req.params;
  const task = await Task.findById(id);
  if (!task) {
    res.status(404);
    throw new Error('Task not found');
  }
  task.isArchived = false;
  const updated = await task.save();
  io.emit('taskRestored', toTaskJson(updated));
  res.json(toTaskJson(updated));
});

// @route GET /api/tasks/user/:userId
// @access Private
const getUserTasks = asyncHandler(async (req, res) => {
  const { userId } = req.params;
  const list = await UserTask.find({ userId }).sort({ assignedAt: -1 });
  res.json(
    await Promise.all(
      list.map(async (ut) => ({
        id: ut._id.toString(),
        userId: ut.userId.toString(),
        taskId: ut.taskId.toString(),
        status: ut.status,
        assignedAt: ut.assignedAt.toISOString(),
        completedAt: ut.completedAt ? ut.completedAt.toISOString() : null,
      }))
    )
  );
});

// @route GET /api/tasks/assigned/:userId
// @access Private
const getAssignedTasks = asyncHandler(async (req, res) => {
  const { userId } = req.params;
  const assignments = await UserTask.find({ userId });
  const taskIds = assignments.map((a) => a.taskId);
  const tasks = await Task.find({ _id: { $in: taskIds }, isArchived: { $ne: true } });
  const userTaskIdMap = Object.fromEntries(assignments.map((a) => [a.taskId.toString(), a._id.toString()]));
  res.json(tasks.map((t) => toTaskJson(t, userTaskIdMap[t._id.toString()])));
});

// @route POST /api/tasks/:taskId/assign/:userId
// @access Private/Admin
const assignTaskToUser = asyncHandler(async (req, res) => {
  const { taskId, userId } = req.params;
  const task = await Task.findById(taskId);

  if (!task) {
    res.status(404);
    throw new Error('Task not found');
  }
  const existing = await UserTask.findOne({ taskId, userId });
  if (existing) {
    return res.status(200).json({
      id: existing._id.toString(),
      userId: existing.userId.toString(),
      taskId: existing.taskId.toString(),
      status: existing.status,
      assignedAt: existing.assignedAt.toISOString(),
      completedAt: existing.completedAt ? existing.completedAt.toISOString() : null,
    });
  }

  const maxActive = await getMaxActiveTasksPerEmployee();

  const activeAssignments = await UserTask.find({
    userId,
    status: { $ne: 'completed' },
  });
  const activeTaskIds = activeAssignments.map((a) => a.taskId);
  const activeTasks = activeTaskIds.length
    ? await Task.find({ _id: { $in: activeTaskIds }, isArchived: { $ne: true } }).select('_id')
    : [];
  const activeCount = activeTasks.length;

  if (activeCount >= maxActive) {
    res.status(400);
    throw new Error(
      `User has reached the maximum number of active tasks (${activeCount}/${maxActive})`,
    );
  }

  const ut = await UserTask.create({ taskId, userId });

  // Auto-set task status on assignment if it hasn't started/completed yet
  if (!isTerminalTaskStatus(task.status) && normalizeTaskStatus(task.status) !== 'in_progress') {
    task.status = 'assigned';
    await task.save();
    io.emit('updatedTask', toTaskJson(task));
  }

  // Fire-and-forget SMS notification for new assignment
  (async () => {
    try {
      const user = await User.findById(userId);
      if (user) {
        await notificationService.notifyTaskAssigned(user, task);
      }
    } catch (e) {
      console.error('Failed to send task assignment SMS:', e.message || e);
    }
  })();

  res.status(201).json({
    id: ut._id.toString(),
    userId: ut.userId.toString(),
    taskId: ut.taskId.toString(),
    status: ut.status,
    assignedAt: ut.assignedAt.toISOString(),
    completedAt: ut.completedAt ? ut.completedAt.toISOString() : null,
  });
});

// @route POST /api/tasks/:taskId/assign-multiple
// @access Private/Admin
const assignTaskToMultipleUsers = asyncHandler(async (req, res) => {
  const { taskId } = req.params;
  const { userIds } = req.body;

  // Validate input
  if (!taskId || taskId.trim() === '') {
    res.status(400);
    throw new Error('Task ID is required');
  }

  if (!Array.isArray(userIds) || userIds.length === 0) {
    res.status(400);
    throw new Error('userIds must be a non-empty array');
  }

  // Validate all user IDs are strings
  if (!userIds.every((id) => typeof id === 'string' && id.trim() !== '')) {
    res.status(400);
    throw new Error('All user IDs must be non-empty strings');
  }

  const task = await Task.findById(taskId);
  if (!task) {
    res.status(404);
    throw new Error('Task not found');
  }

  // Auto-set task status on assignment if it hasn't started/completed yet
  if (!isTerminalTaskStatus(task.status) && normalizeTaskStatus(task.status) !== 'in_progress') {
    task.status = 'assigned';
    await task.save();
    io.emit('updatedTask', toTaskJson(task));
  }

  const maxActive = await getMaxActiveTasksPerEmployee();

  const nonCompletedAssignments = await UserTask.find({
    userId: { $in: userIds },
    status: { $ne: 'completed' },
  });

  const activeTaskIds = nonCompletedAssignments.map((a) => a.taskId);
  const activeTasks = activeTaskIds.length
    ? await Task.find({
        _id: { $in: activeTaskIds },
        isArchived: { $ne: true },
      }).select('_id')
    : [];
  const activeTaskIdSet = new Set(activeTasks.map((t) => t._id.toString()));
  const activeCounts = new Map();
  for (const a of nonCompletedAssignments) {
    if (!activeTaskIdSet.has(a.taskId.toString())) continue;
    const key = a.userId.toString();
    activeCounts.set(key, (activeCounts.get(key) || 0) + 1);
  }

  const results = [];
  for (const userId of userIds) {
    try {
      // Validate user exists
      const user = await User.findById(userId);

      if (!user) {
        console.log(`User not found: ${userId}`);
        results.push({
          userId,
          success: false,
          message: `User not found`,
        });
        continue;
      }

      const existing = await UserTask.findOne({ taskId, userId });
      if (existing) {
        results.push({
          userId,

          success: true,
          message: 'Already assigned',
          data: {
            id: existing._id.toString(),
            userId: existing.userId.toString(),
            taskId: existing.taskId.toString(),
            status: existing.status,
            assignedAt: existing.assignedAt.toISOString(),
            completedAt: existing.completedAt ? existing.completedAt.toISOString() : null,
          },
        });
      } else {
        const currentActive = activeCounts.get(userId) || 0;
        if (currentActive >= maxActive) {
          results.push({
            userId,
            success: false,
            message: `User has reached maximum active tasks (${currentActive}/${maxActive})`,
          });
          continue;
        }

        const ut = await UserTask.create({ taskId, userId });
        activeCounts.set(userId, currentActive + 1);

        // Fire-and-forget SMS per newly assigned user
        (async () => {
          try {
            const user = await User.findById(userId);
            if (user) {
              await notificationService.notifyTaskAssigned(user, task);
            }
          } catch (e) {
            console.error('Failed to send multi-assign SMS:', e.message || e);
          }
        })();

        results.push({
          userId,
          success: true,
          message: 'Assigned successfully',
          data: {
            id: ut._id.toString(),
            userId: ut.userId.toString(),
            taskId: ut.taskId.toString(),
            status: ut.status,
            assignedAt: ut.assignedAt.toISOString(),
            completedAt: ut.completedAt ? ut.completedAt.toISOString() : null,
          },
        });
      }
    } catch (e) {
      console.error(`Error assigning task to user ${userId}:`, e);
      results.push({
        userId,
        success: false,
        message: `Failed to assign: ${e.message}`,
      });
    }
  }

  const successCount = results.filter((r) => r.success).length;
  const failedCount = results.filter((r) => !r.success).length;

  // Always return 201 with results, even if some failed
  const statusCode = successCount > 0 ? 201 : 400;

  if (successCount > 0) {
    io.emit('taskAssignedToMultiple', { taskId, userIds: results.filter((r) => r.success).map((r) => r.userId) });
  }

  res.status(statusCode).json({
    taskId,
    results,
    summary: {
      total: userIds.length,
      successful: successCount,
      failed: failedCount,
    },
  });
});

// @route PUT /api/tasks/user-task/:userTaskId/status
// @access Private
const updateUserTaskStatus = asyncHandler(async (req, res) => {
  const { userTaskId } = req.params;
  const { status } = req.body;
  const normalizedNextStatus = normalizeTaskStatus(status);
  const ut = await UserTask.findById(userTaskId);
  if (!ut) {
    res.status(404);
    throw new Error('UserTask not found');
  }
  const nextStatus = normalizedNextStatus;

  // Validate transition against the owning Task (if it still exists)
  let taskForStatusUpdate = null;
  try {
    taskForStatusUpdate = await Task.findById(ut.taskId);
  } catch (_) {
    taskForStatusUpdate = null;
  }

  if (taskForStatusUpdate && !canTransitionTaskStatus(taskForStatusUpdate.status, nextStatus)) {
    res.status(400);
    throw new Error(
      `Invalid task status transition from ${taskForStatusUpdate.status || 'none'} to ${nextStatus}`,
    );
  }

  ut.status = nextStatus;
  if (nextStatus === 'completed') {
    ut.completedAt = new Date();
  } else if (!nextStatus || nextStatus === 'pending') {
    ut.completedAt = undefined;
  }
  await ut.save();

  // IMPORTANT: Also update the Task status and basic progress so frontend sees the change
  if (taskForStatusUpdate) {
    taskForStatusUpdate.status = nextStatus;

    // Simple default progress mapping; can be overridden manually via progressPercent API
    if (nextStatus === 'in_progress' &&
        (typeof taskForStatusUpdate.progressPercent !== 'number' || taskForStatusUpdate.progressPercent < 1)) {
      taskForStatusUpdate.progressPercent = 50;
    } else if (nextStatus === 'completed') {
      taskForStatusUpdate.progressPercent = 100;
    }

    try {
      await taskForStatusUpdate.save();
      console.log(`✓ Updated Task ${ut.taskId} status to ${nextStatus}`);
    } catch (e) {
      console.warn(`⚠️ Failed to update Task status: ${e.message}`);
    }
  }

  // Auto-create a simple task report on completion
  if (status === 'completed') {
    try {
      await Report.create({
        type: 'task',
        task: ut.taskId,
        employee: ut.userId,
        content: 'Task marked completed',
      });
      io.emit('newReport', { type: 'task', taskId: ut.taskId.toString(), userId: ut.userId.toString() });
    } catch (e) {
      console.error('Failed to auto-create task completion report:', e);
    }
  }
  io.emit('updatedUserTaskStatus', {
    id: ut._id.toString(),
    userId: ut.userId.toString(),
    taskId: ut.taskId.toString(),
    status: ut.status,
    assignedAt: ut.assignedAt.toISOString(),
    completedAt: ut.completedAt ? ut.completedAt.toISOString() : null,
  }); // Emit real-time event

  // Emit admin notification so dashboards can react to employee actions
  try {
    const user = await User.findById(ut.userId).select('name email');
    const actorName = user?.name || 'Employee';
    let action = nextStatus;
    if (nextStatus === 'in_progress') {
      action = 'accepted';
    } else if (nextStatus === 'completed') {
      action = 'completed';
    }

    io.emit('adminNotification', {
      type: 'task',
      action,
      taskId: ut.taskId.toString(),
      userTaskId: ut._id.toString(),
      employeeId: ut.userId.toString(),
      employeeName: actorName,
      timestamp: new Date(),
      message:
        action === 'accepted'
          ? `${actorName} accepted and started a task`
          : action === 'completed'
              ? `${actorName} completed a task`
              : `${actorName} updated task status to ${nextStatus}`,
      severity: action === 'completed' ? 'info' : 'warning',
    });
  } catch (e) {
    console.warn('Failed to emit task status adminNotification:', e.message || e);
  }

  res.json({
    id: ut._id.toString(),
    userId: ut.userId.toString(),
    taskId: ut.taskId.toString(),
    status: ut.status,
    assignedAt: ut.assignedAt.toISOString(),
    completedAt: ut.completedAt ? ut.completedAt.toISOString() : null,
  });
});

const escalateTask = asyncHandler(async (req, res) => {
  const { id } = req.params;
  const task = await Task.findById(id);
  if (!task) {
    res.status(404);
    throw new Error('Task not found');
  }

  const assignments = await UserTask.find({
    taskId: task._id,
    status: { $ne: 'completed' },
  });

  if (!assignments.length) {
    return res.status(200).json({ sent: 0, targets: [] });
  }

  const userIds = assignments.map((a) => a.userId);
  const users = await User.find({
    _id: { $in: userIds },
    phone: { $exists: true, $ne: '' },
    isActive: true,
  }).select('phone');

  if (!users.length) {
    return res.status(200).json({ sent: 0, targets: [] });
  }

  await Promise.all(
    users.map((u) => notificationService.notifyTaskEscalated(u, task))
  );

  res.status(200).json({
    sent: users.length,
    targets: users.map((u) => u._id.toString()),
  });
});

// @route PUT /api/tasks/:id/checklist-item
// @access Private (assigned employee or admin)
const updateTaskChecklistItem = asyncHandler(async (req, res) => {
  const { id } = req.params;
  const { index, isCompleted } = req.body;

  const task = await Task.findById(id);
  if (!task) {
    res.status(404);
    throw new Error('Task not found');
  }

  if (!req.user) {
    res.status(401);
    throw new Error('Not authenticated');
  }

  if (req.user.role !== 'admin') {
    const isAssigned = await UserTask.exists({ taskId: task._id, userId: req.user._id });
    if (!isAssigned) {
      res.status(403);
      throw new Error('Not authorized to update this task');
    }
  }

  const idx = Number(index);
  if (
    !Number.isInteger(idx) ||
    idx < 0 ||
    !Array.isArray(task.checklist) ||
    idx >= task.checklist.length
  ) {
    res.status(400);
    throw new Error('Invalid checklist index');
  }

  const item = task.checklist[idx];
  const complete = !!isCompleted;
  item.isCompleted = complete;
  item.completedAt = complete ? new Date() : undefined;

  recalculateChecklistProgress(task);

  const updated = await task.save();
  io.emit('updatedTask', toTaskJson(updated));
  res.json(toTaskJson(updated));
});

// @route PUT /api/tasks/:id/block
// @access Private (assigned employee or admin)
const blockTask = asyncHandler(async (req, res) => {
  const { id } = req.params;
  const { reason } = req.body;

  const task = await Task.findById(id);
  if (!task) {
    res.status(404);
    throw new Error('Task not found');
  }

  if (!req.user) {
    res.status(401);
    throw new Error('Not authenticated');
  }

  if (req.user.role !== 'admin') {
    const isAssigned = await UserTask.exists({ taskId: task._id, userId: req.user._id });
    if (!isAssigned) {
      res.status(403);
      throw new Error('Not authorized to update this task');
    }
  }

  task.status = 'blocked';
  task.blockReason =
    typeof reason === 'string' && reason.trim().length > 0
      ? reason.trim()
      : 'No reason provided';

  const updated = await task.save();

  // Create a simple task report so admins can see the block reason
  try {
    const report = await Report.create({
      type: 'task',
      task: updated._id,
      employee: req.user._id,
      content: `Task blocked: ${updated.blockReason}`,
    });
    io.emit('newReport', report);
  } catch (e) {
    console.error('Failed to create task blocked report:', e);
  }

  io.emit('updatedTask', toTaskJson(updated));
  res.json(toTaskJson(updated));
});

module.exports = {
  getTask,
  getTasks,
  getCurrentTasks,
  getArchivedTasks,
  createTask,
  updateTask,
  deleteTask,
  getUserTasks,
  getAssignedTasks,
  assignTaskToUser,
  assignTaskToMultipleUsers,
  updateUserTaskStatus,
  updateTaskChecklistItem,
  blockTask,
  archiveTask,
  restoreTask,
  escalateTask,
};