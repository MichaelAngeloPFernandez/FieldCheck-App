const asyncHandler = require('express-async-handler');
const Task = require('../models/Task');
const UserTask = require('../models/UserTask');
const User = require('../models/User');
const { io } = require('../server');
const Report = require('../models/Report');
const Attendance = require('../models/Attendance');
const Settings = require('../models/Settings');
const notificationService = require('../services/notificationService');
const appNotificationService = require('../services/appNotificationService');

async function getMaxActiveTasksPerEmployee() {
  return 3;
}

const TERMINAL_TASK_STATUSES = ['completed', 'reviewed', 'closed'];

function normalizeTaskStatus(status) {
  if (!status) return 'pending';
  return String(status).toLowerCase();
}

function isTerminalTaskStatus(status) {
  return TERMINAL_TASK_STATUSES.includes(normalizeTaskStatus(status));
}

function doesTaskCountTowardActiveLimit(taskDoc, now = new Date()) {
  if (!taskDoc) return false;
  if (taskDoc.isArchived) return false;
  if (isTerminalTaskStatus(taskDoc.status)) return false;
  if (taskDoc.dueDate && taskDoc.dueDate < now) return false;
  return true;
}

function isBlockedAssignment(ut) {
  if (!ut) return false;
  const s = String(ut.status || '').toLowerCase();
  if (s === 'blocked') return true;
  const b = String(ut.blockStatus || '').toLowerCase();
  return b === 'blocked';
}

async function countActiveNonOverdueTasksForUser(userId) {
  const now = new Date();
  const assignments = await UserTask.find({
    userId,
    isArchived: { $ne: true },
    status: { $ne: 'completed' },
  }).select('taskId');

  const taskIds = assignments.map((a) => a.taskId).filter(Boolean);
  const tasks = taskIds.length
    ? await Task.find({ _id: { $in: taskIds }, isArchived: { $ne: true } }).select(
        '_id dueDate status isArchived',
      )
    : [];

  return tasks.filter((t) => doesTaskCountTowardActiveLimit(t, now)).length;
}

async function trimOverLimitAssignmentsForUser(userId, maxActive) {
  const now = new Date();

  const assignments = await UserTask.find({
    userId,
    isArchived: { $ne: true },
    status: { $ne: 'completed' },
  })
    .sort({ assignedAt: 1 })
    .select('_id userId taskId assignedAt isArchived status');

  if (!assignments.length) return 0;

  const taskIds = assignments.map((a) => a.taskId).filter(Boolean);
  const tasks = taskIds.length
    ? await Task.find({ _id: { $in: taskIds }, isArchived: { $ne: true } }).select(
        '_id dueDate status isArchived',
      )
    : [];

  const taskMap = new Map(tasks.map((t) => [t._id.toString(), t]));
  const countable = assignments.filter((a) => {
    const t = taskMap.get(a.taskId?.toString() || '');
    return doesTaskCountTowardActiveLimit(t, now);
  });

  if (countable.length <= maxActive) return 0;

  const toArchive = countable.slice(0, countable.length - maxActive);
  for (const ut of toArchive) {
    if (ut.isArchived) continue;
    ut.isArchived = true;
    await ut.save();

    io.emit('userTaskArchived', {
      id: ut._id.toString(),
      userId: ut.userId.toString(),
      taskId: ut.taskId.toString(),
    });
    io.emit('taskUnassigned', {
      taskId: ut.taskId.toString(),
      userId: ut.userId.toString(),
    });
  }

  return toArchive.length;
}

function canTransitionTaskStatus(fromStatus, toStatus) {
  const from = normalizeTaskStatus(fromStatus);
  const to = normalizeTaskStatus(toStatus);

  if (from === to) return true;
  if (isTerminalTaskStatus(from) && !isTerminalTaskStatus(to)) {
    return false;
  }

  return true;
}

function recalculateChecklistProgress(taskDoc) {
  if (!Array.isArray(taskDoc.checklist) || taskDoc.checklist.length === 0) {
    return;
  }

  const total = taskDoc.checklist.length;
  const completed = taskDoc.checklist.filter((item) => item && item.isCompleted)
    .length;
  if (!total) {
    return;
  }

  const percent = Math.round((completed / total) * 100);
  if (!Number.isNaN(percent)) {
    taskDoc.progressPercent = Math.max(0, Math.min(100, percent));
  }
}

function toTaskJson(doc, userTaskId) {
  const now = new Date();
  const isOverdue =
    !!doc.dueDate &&
    doc.dueDate < now &&
    normalizeTaskStatus(doc.status) !== 'completed' &&
    !doc.isArchived;

  const rawStatus = normalizeTaskStatus(doc.status);

  let uiStatus = rawStatus || 'pending';
  if (['created', 'assigned', 'accepted'].includes(rawStatus)) {
    uiStatus = 'pending';
  } else if (['blocked', 'in_progress'].includes(rawStatus)) {
    uiStatus = 'in_progress';
  } else if (['completed', 'reviewed', 'closed'].includes(rawStatus)) {
    uiStatus = 'completed';
  }

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
    isLate: false, // Per-assignee isLate is overridden in getAssignedTasks
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

const getTask = asyncHandler(async (req, res) => {
  const { id } = req.params;
  const task = await Task.findById(id);
  if (!task) {
    res.status(404);
    throw new Error('Task not found');
  }
  res.json(toTaskJson(task));
});

const getTasks = asyncHandler(async (req, res) => {
  const { archived, startDate, endDate } = req.query;

  const filter = {};
  if (archived === 'true') {
    filter.isArchived = true;
  } else if (archived === 'false' || archived === undefined) {
    filter.isArchived = { $ne: true };
  }

  if (startDate || endDate) {
    filter.createdAt = {};
    if (startDate) {
      filter.createdAt.$gte = new Date(startDate);
    }
    if (endDate) {
      filter.createdAt.$lte = new Date(endDate);
    }
  }

  const tasks = await Task.find(filter).sort({ createdAt: -1 });
  res.json(tasks.map((t) => toTaskJson(t)));
});

const getTaskAssignees = asyncHandler(async (req, res) => {
  const { taskId } = req.params;

  const task = await Task.findById(taskId).select('_id').lean();
  if (!task) {
    res.status(404);
    throw new Error('Task not found');
  }

  const assignments = await UserTask.find({ taskId: task._id, isArchived: { $ne: true } })
    .populate('userId', 'name employeeId username role')
    .sort({ assignedAt: -1 });

  res.json(
    assignments.map((ut) => {
      const u = ut.userId && typeof ut.userId === 'object' ? ut.userId : null;
      return {
        userTaskId: ut._id.toString(),
        taskId: ut.taskId.toString(),
        userId: u && u._id ? u._id.toString() : ut.userId.toString(),
        name: u && u.name ? u.name : undefined,
        employeeId: u && u.employeeId ? u.employeeId : undefined,
        username: u && u.username ? u.username : undefined,
        status: ut.status,
        progressPercent: typeof ut.progressPercent === 'number' ? ut.progressPercent : 0,
        assignedAt: ut.assignedAt ? ut.assignedAt.toISOString() : null,
        completedAt: ut.completedAt ? ut.completedAt.toISOString() : null,
        blockStatus: ut.blockStatus,
        blockReasonCategory: ut.blockReasonCategory,
        blockReasonText: ut.blockReasonText,
        blockEvidencePhotos: Array.isArray(ut.blockEvidencePhotos) ? ut.blockEvidencePhotos : [],
        blockedAt: ut.blockedAt ? ut.blockedAt.toISOString() : null,
        adminReviewNote: ut.adminReviewNote,
        adminAction: ut.adminAction,
        adminActionAt: ut.adminActionAt ? ut.adminActionAt.toISOString() : null,
        adminActionBy: ut.adminActionBy ? ut.adminActionBy.toString() : null,
      };
    }),
  );
});

const getCurrentTasks = asyncHandler(async (req, res) => {
  const tasks = await Task.find({ isArchived: { $ne: true } }).sort({ createdAt: -1 });
  res.json(tasks.map((t) => toTaskJson(t)));
});

const getArchivedTasks = asyncHandler(async (req, res) => {
  const tasks = await Task.find({ isArchived: true }).sort({ createdAt: -1 });
  res.json(tasks.map((t) => toTaskJson(t)));
});

const getOverdueTasks = asyncHandler(async (req, res) => {
  const now = new Date();
  const tasks = await Task.find({
    isArchived: { $ne: true },
    dueDate: { $lt: now },
    status: { $nin: ['completed', 'reviewed', 'closed'] },
  }).sort({ dueDate: 1 });
  res.json(tasks.map((t) => toTaskJson(t)));
});

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
  io.emit('newTask', toTaskJson(task));

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
  if (
    req.body.description &&
    typeof req.body.description === 'string' &&
    req.body.description.length > 5000
  ) {
    res.status(400);
    throw new Error('Description is too long (max 5000 characters)');
  }

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

const deleteTask = asyncHandler(async (req, res) => {
  const { id } = req.params;
  const task = await Task.findById(id);
  if (!task) {
    return res.status(404).json({ message: 'Task not found' });
  }
  await UserTask.deleteMany({ taskId: task._id });
  await task.deleteOne();
  io.emit('deletedTask', id);
  res.status(204).send();
});

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
      })),
    ),
  );
});

const getAssignedTasks = asyncHandler(async (req, res) => {
  const { userId } = req.params;
  const archived = String(req.query.archived || 'false').trim().toLowerCase() === 'true';

  const assignments = await UserTask.find({
    userId,
    isArchived: archived ? true : { $ne: true },
  });
  const taskIds = assignments.map((a) => a.taskId);

  // IMPORTANT: For employee task lists, archive state is driven by UserTask,
  // not Task.isArchived. Do not filter out tasks by Task.isArchived here.
  const tasks = await Task.find({ _id: { $in: taskIds } });
  const assignmentByTaskId = new Map(
    assignments.map((a) => [a.taskId.toString(), a]),
  );

  res.json(
    tasks.map((t) => {
      const a = assignmentByTaskId.get(t._id.toString());
      const now = new Date();
      const dueDate = t && t.dueDate ? new Date(t.dueDate) : null;
      const assigneeStatus = a ? normalizeTaskStatus(a.status) : '';
      const isAssigneeCompleted = assigneeStatus === 'completed';

      const isOverdueForAssignee =
        !!dueDate && dueDate < now && !isAssigneeCompleted && !archived;
      const isLateForAssignee =
        !!dueDate &&
        isAssigneeCompleted &&
        a &&
        a.completedAt &&
        new Date(a.completedAt) > dueDate;

      const base = {
        ...toTaskJson(t, a ? a._id.toString() : undefined),
        userTaskStatus: a ? a.status : undefined,
        userTaskAssignedAt:
          a && a.assignedAt ? a.assignedAt.toISOString() : undefined,
        userTaskCompletedAt:
          a && a.completedAt ? a.completedAt.toISOString() : undefined,
        blockStatus: a ? a.blockStatus : undefined,
        blockReasonCategory: a ? a.blockReasonCategory : undefined,
        blockReasonText: a ? a.blockReasonText : undefined,
        blockEvidencePhotos: a ? a.blockEvidencePhotos : undefined,
        blockedAt: a && a.blockedAt ? a.blockedAt.toISOString() : undefined,
        adminReviewNote: a ? a.adminReviewNote : undefined,
        adminAction: a ? a.adminAction : undefined,
        adminActionAt: a && a.adminActionAt ? a.adminActionAt.toISOString() : undefined,
        // Override task-level computed flags with per-assignee truth.
        isOverdue: isOverdueForAssignee,
        isLate: !!isLateForAssignee,
        // Grading UI fields
        gradeScore:
          a && a.grade && typeof a.grade.score === 'number'
            ? a.grade.score
            : undefined,
        gradeFeedback:
          a && a.grade && a.grade.feedback ? a.grade.feedback : undefined,
        isGraded: !!(a && a.grade && a.grade.score !== undefined),
      };

      if (a && (!Array.isArray(t.checklist) || t.checklist.length === 0)) {
        const p = typeof a.progressPercent === 'number' ? a.progressPercent : 0;
        base.progressPercent = Math.max(0, Math.min(100, Math.round(p)));
      }

      return base;
    }),
  );
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

  // Auto-heal legacy over-limit users (e.g., 4/3) back down to max.
  await trimOverLimitAssignmentsForUser(userId, maxActive);

  const activeCount = await countActiveNonOverdueTasksForUser(userId);

  if (activeCount >= maxActive) {
    res.status(400);
    throw new Error(
      `User has reached the maximum number of active tasks (${activeCount}/${maxActive})`,
    );
  }

  const ut = await UserTask.create({ taskId, userId });

  // Reuse existing client handlers by emitting the "multiple" event with a single user.
  io.emit('taskAssignedToMultiple', { taskId, userIds: [userId] });

  // Auto-set task status on assignment if it hasn't started/completed yet
  if (!isTerminalTaskStatus(task.status) && normalizeTaskStatus(task.status) !== 'in_progress') {
    task.status = 'assigned';
    await task.save();
    io.emit('updatedTask', toTaskJson(task));
  }

  // Fire-and-forget in-app notification for new assignment
  (async () => {
    try {
      const user = await User.findById(userId);
      if (user) {
        try {
          await appNotificationService.createNotification({
            recipientUserId: userId,
            scope: 'tasks',
            type: 'info',
            action: 'task_assigned',
            title: 'New task assigned',
            message: `You were assigned: ${task.title}`,
            payload: { taskId: String(task._id) },
          });
        } catch (_) {}
      }
    } catch (e) {
      console.error('Failed to create task assignment notification:', e.message || e);
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

  // Auto-heal legacy over-limit users (e.g., 4/3) back down to max before counting.
  await Promise.all(
    [...new Set(userIds)].map(async (uid) => {
      try {
        await trimOverLimitAssignmentsForUser(uid, maxActive);
      } catch (_) {}
    }),
  );

  const nonCompletedAssignments = await UserTask.find({
    userId: { $in: userIds },
    isArchived: { $ne: true },
    status: { $ne: 'completed' },
  }).select('userId taskId');

  const now = new Date();
  const allTaskIds = nonCompletedAssignments.map((a) => a.taskId).filter(Boolean);
  const activeTasks = allTaskIds.length
    ? await Task.find({ _id: { $in: allTaskIds }, isArchived: { $ne: true } }).select(
        '_id dueDate status isArchived',
      )
    : [];

  const countableTaskIdSet = new Set(
    activeTasks
      .filter((t) => doesTaskCountTowardActiveLimit(t, now))
      .map((t) => t._id.toString()),
  );

  const activeCounts = new Map();
  for (const a of nonCompletedAssignments) {
    const taskIdStr = a.taskId?.toString();
    if (!taskIdStr || !countableTaskIdSet.has(taskIdStr)) continue;
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

        // Fire-and-forget in-app notification per newly assigned user
        (async () => {
          try {
            const user = await User.findById(userId);
            if (user) {
              try {
                await appNotificationService.createNotification({
                  recipientUserId: userId,
                  scope: 'tasks',
                  type: 'info',
                  action: 'task_assigned',
                  title: 'New task assigned',
                  message: `You were assigned: ${task.title}`,
                  payload: { taskId: String(task._id) },
                });
              } catch (_) {}
            }
          } catch (e) {
            console.error('Failed to create task assignment notification:', e.message || e);
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
// @access Private
const updateUserTaskStatus = asyncHandler(async (req, res) => {
  const { userTaskId } = req.params;
  const { status, progressPercent } = req.body;
  let progressValue;
  if (progressPercent !== undefined) {
    const parsed = Number(progressPercent);
    if (!Number.isFinite(parsed) || parsed < 0 || parsed > 100) {
      res.status(400);
      throw new Error('progressPercent must be a number between 0 and 100');
    }
    progressValue = Math.round(parsed);
  }

  const ut = await UserTask.findById(userTaskId);
  if (!ut) {
    res.status(404);
    throw new Error('UserTask not found');
  }

  const nextStatus = status;

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

  // Enforce per-assignee acceptance gate
  const currentAssignmentStatus = String(ut.status || '').toLowerCase();
  const requested = String(nextStatus || '').toLowerCase();
  if (
    ['pending', 'pending_acceptance'].includes(currentAssignmentStatus) &&
    ['in_progress', 'completed'].includes(requested)
  ) {
    res.status(403);
    throw new Error('Task must be accepted before starting');
  }

  ut.status = nextStatus;
  if (progressValue !== undefined) {
    ut.progressPercent = progressValue;
  }
  if (nextStatus === 'completed') {
    ut.completedAt = new Date();
  } else if (!nextStatus || nextStatus === 'pending' || nextStatus === 'pending_acceptance') {
    ut.completedAt = undefined;
  }

  await ut.save();

  // IMPORTANT: Do not overwrite global Task.status from per-assignee status.
  // Keep Task.status as an aggregate state for admin/UI convenience.
  if (taskForStatusUpdate) {
    try {
      const allAssignments = await UserTask.find({
        taskId: taskForStatusUpdate._id,
        isArchived: { $ne: true },
      }).select('status');

      const statuses = allAssignments.map((a) => String(a.status || '').toLowerCase());
      const anyInProgress = statuses.some((s) => s === 'in_progress');
      const allCompleted = statuses.length > 0 && statuses.every((s) => s === 'completed');

      if (progressValue !== undefined) {
        taskForStatusUpdate.progressPercent = progressValue;
      }

      if (allCompleted) {
        taskForStatusUpdate.status = 'completed';
        if (
          progressValue === undefined &&
          (typeof taskForStatusUpdate.progressPercent !== 'number' ||
            taskForStatusUpdate.progressPercent < 1)
        ) {
          taskForStatusUpdate.progressPercent = 100;
        }
      } else if (anyInProgress) {
        taskForStatusUpdate.status = 'in_progress';
        if (
          progressValue === undefined &&
          (typeof taskForStatusUpdate.progressPercent !== 'number' ||
            taskForStatusUpdate.progressPercent < 1)
        ) {
          taskForStatusUpdate.progressPercent = 50;
        }
      }

      await taskForStatusUpdate.save();
      console.log(`✓ Updated Task ${ut.taskId} aggregate status`);
    } catch (e) {
      console.warn(`⚠️ Failed to update Task status: ${e.message}`);
    }
  }

  // Auto-create a simple task report on completion
  if (status === 'completed') {
    try {
      const existing = await Report.findOne({
        type: 'task',
        task: ut.taskId,
        employee: ut.userId,
      })
        .sort({ submittedAt: -1 })
        .select('content attachments');

      const hasMeaningfulReport =
        existing &&
        ((Array.isArray(existing.attachments) && existing.attachments.length > 0) ||
          (typeof existing.content === 'string' &&
            existing.content.trim().length > 0 &&
            existing.content.trim() !== 'Task marked completed'));

      if (!hasMeaningfulReport) {
        await Report.create({
          type: 'task',
          task: ut.taskId,
          employee: ut.userId,
          content: 'Task marked completed',
        });
        io.emit('newReport', {
          type: 'task',
          taskId: ut.taskId.toString(),
          userId: ut.userId.toString(),
        });
      }
    } catch (e) {
      console.error('Failed to auto-create task completion report:', e);
    }
  }

  // Emit employeeLocationUpdate so admin dashboards update status/marker color
  // even when the employee is not continuously streaming GPS.
  try {
    const userId = ut.userId;
    const now = new Date();

    const activeTaskCount = await UserTask.countDocuments({
      userId,
      isArchived: { $ne: true },
      status: { $ne: 'completed' },
    });

    // Best-effort: keep user's active task count in sync
    try {
      await User.findByIdAndUpdate(userId, { activeTaskCount });
    } catch (_) {}

    const user = await User.findById(userId).select(
      'name username lastLatitude lastLongitude lastLocationUpdate isOnline',
    );

    const latitude = user && typeof user.lastLatitude === 'number' ? user.lastLatitude : null;
    const longitude = user && typeof user.lastLongitude === 'number' ? user.lastLongitude : null;

    if (typeof latitude === 'number' && typeof longitude === 'number') {
      const inProgressCount = await UserTask.countDocuments({
        userId,
        isArchived: { $ne: true },
        status: 'in_progress',
      });

      const openAttendance = await Attendance.findOne({
        employee: userId,
        checkOut: { $exists: false },
        isVoid: { $ne: true },
      })
        .populate('geofence', 'name')
        .select('geofence')
        .lean();

      const geofenceName =
        openAttendance && openAttendance.geofence
          ? openAttendance.geofence.name || null
          : null;

      let derivedStatus = 'moving';
      if (inProgressCount > 0 || nextStatus === 'in_progress') {
        derivedStatus = 'busy';
      } else if (openAttendance) {
        derivedStatus = 'available';
      }

      io.emit('employeeLocationUpdate', {
        employeeId: userId.toString(),
        name: user && user.name ? String(user.name) : 'Employee',
        username: user && user.username ? String(user.username) : null,
        latitude,
        longitude,
        accuracy: 0,
        speed: 0,
        status: derivedStatus,
        timestamp: (
          user && user.lastLocationUpdate
            ? new Date(user.lastLocationUpdate).toISOString()
            : now.toISOString()
        ),
        activeTaskCount,
        workloadScore: 0,
        currentGeofence: geofenceName,
        distanceToNearestTask: null,
        isOnline: user && typeof user.isOnline === 'boolean' ? user.isOnline : true,
        batteryLevel: null,
      });
    }
  } catch (_) {}

  io.emit('updatedUserTaskStatus', {
    id: ut._id.toString(),
    userId: ut.userId.toString(),
    taskId: ut.taskId.toString(),
    status: ut.status,
    assignedAt: ut.assignedAt.toISOString(),
    completedAt: ut.completedAt ? ut.completedAt.toISOString() : null,
    progressPercent: ut.progressPercent,
  }); // Emit real-time event
  res.json({
    id: ut._id.toString(),
    userId: ut.userId.toString(),
    taskId: ut.taskId.toString(),
    status: ut.status,
    assignedAt: ut.assignedAt.toISOString(),
    completedAt: ut.completedAt ? ut.completedAt.toISOString() : null,
    progressPercent: ut.progressPercent,
  });
});

// @route POST /api/tasks/user-task/:userTaskId/accept
// @access Private
const acceptUserTask = asyncHandler(async (req, res) => {
  const { userTaskId } = req.params;
  const ut = await UserTask.findById(userTaskId);

  if (!ut) {
    res.status(404);
    throw new Error('UserTask not found');
  }

  if (!req.user) {
    res.status(401);
    throw new Error('Not authenticated');
  }

  if (req.user.role !== 'admin' && ut.userId.toString() !== req.user._id.toString()) {
    res.status(403);
    throw new Error('Not authorized to accept this task assignment');
  }

  const current = String(ut.status || '').toLowerCase();
  if (['accepted', 'in_progress', 'completed'].includes(current)) {
    return res.status(200).json({
      id: ut._id.toString(),
      userId: ut.userId.toString(),
      taskId: ut.taskId.toString(),
      status: ut.status,
      assignedAt: ut.assignedAt.toISOString(),
      completedAt: ut.completedAt ? ut.completedAt.toISOString() : null,
    });
  }

  ut.status = 'accepted';
  ut.completedAt = undefined;
  await ut.save();

  io.emit('updatedUserTaskStatus', {
    id: ut._id.toString(),
    userId: ut.userId.toString(),
    taskId: ut.taskId.toString(),
    status: ut.status,
    assignedAt: ut.assignedAt.toISOString(),
    completedAt: ut.completedAt ? ut.completedAt.toISOString() : null,
  });

  res.status(200).json({
    id: ut._id.toString(),
    userId: ut.userId.toString(),
    taskId: ut.taskId.toString(),
    status: ut.status,
    assignedAt: ut.assignedAt.toISOString(),
    completedAt: ut.completedAt ? ut.completedAt.toISOString() : null,
  });
});

// @route POST /api/tasks/user-task/:userTaskId/cancel
// @desc Employee cancels an accepted/in-progress task (resets to pending_acceptance)
// @access Private
const cancelUserTask = asyncHandler(async (req, res) => {
  const { userTaskId } = req.params;
  const { reason } = req.body;

  const cancelReason = (reason ?? '').toString().trim();
  if (!cancelReason) {
    res.status(400);
    throw new Error('Cancellation reason is required');
  }

  const ut = await UserTask.findById(userTaskId);
  if (!ut) {
    res.status(404);
    throw new Error('UserTask not found');
  }

  if (!req.user) {
    res.status(401);
    throw new Error('Not authenticated');
  }

  if (req.user.role !== 'admin' && ut.userId.toString() !== req.user._id.toString()) {
    res.status(403);
    throw new Error('Not authorized to cancel this task assignment');
  }

  const current = String(ut.status || '').toLowerCase();
  if (!['accepted', 'in_progress'].includes(current)) {
    res.status(400);
    throw new Error('Only accepted or in-progress tasks can be cancelled');
  }

  ut.status = 'pending_acceptance';
  ut.progressPercent = 0;
  ut.cancelReason = cancelReason;
  ut.cancelledAt = new Date();
  ut.completedAt = undefined;
  await ut.save();

  // Emit real-time event
  io.emit('taskCancelled', {
    id: ut._id.toString(),
    userId: ut.userId.toString(),
    taskId: ut.taskId.toString(),
    status: ut.status,
    cancelReason: ut.cancelReason,
    cancelledAt: ut.cancelledAt ? ut.cancelledAt.toISOString() : null,
  });

  // Fire-and-forget admin notification
  setImmediate(async () => {
    try {
      const task = await Task.findById(ut.taskId).select('title');
      const who = [
        (req.user?.name || '').toString().trim(),
        (req.user?.employeeId || '').toString().trim(),
      ].filter(Boolean);
      const whoLabel = who.join(' \u2022 ');
      const taskTitle = task ? task.title : 'Unknown task';
      const msg = whoLabel
        ? `${whoLabel} cancelled task: ${taskTitle}`
        : `Task cancelled: ${taskTitle}`;

      await appNotificationService.createForAdmins({
        excludeUserId: req.user?._id,
        type: 'task',
        action: 'task_cancelled',
        title: 'Task Cancelled',
        message: msg,
        payload: {
          taskId: String(ut.taskId),
          userTaskId: String(ut._id),
          employeeId: (req.user?.employeeId || '').toString(),
          employeeName: (req.user?.name || '').toString(),
          userId: String(req.user?._id || ''),
          cancelReason,
        },
      });
    } catch (e) {
      console.error('Failed to create task cancellation notification:', e.message || e);
    }
  });

  res.status(200).json({
    id: ut._id.toString(),
    userId: ut.userId.toString(),
    taskId: ut.taskId.toString(),
    status: ut.status,
    cancelReason: ut.cancelReason,
    cancelledAt: ut.cancelledAt ? ut.cancelledAt.toISOString() : null,
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
  const {
    reasonCategory,
    reasonText,
    evidencePhotos,
    reason,
  } = req.body;

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

  // Block is per-assignment (UserTask) NOT global on Task.
  const ut = await UserTask.findOne({
    taskId: task._id,
    userId: req.user._id,
    isArchived: { $ne: true },
  });

  if (!ut) {
    res.status(403);
    throw new Error('Not authorized to update this task');
  }

  const current = normalizeTaskStatus(ut.status);
  if (isTerminalTaskStatus(current)) {
    res.status(400);
    throw new Error('Completed tasks cannot be blocked');
  }

  const category = (reasonCategory ?? '').toString().trim();
  const text = (reasonText ?? reason ?? '').toString().trim();
  if (!text) {
    res.status(400);
    throw new Error('Block reason is required');
  }

  const photos = Array.isArray(evidencePhotos)
    ? evidencePhotos
        .map((p) => (p == null ? '' : String(p)).trim())
        .filter(Boolean)
        .slice(0, 3)
    : [];

  ut.status = 'blocked';
  ut.blockStatus = 'blocked';
  ut.blockReasonCategory = category;
  ut.blockReasonText = text;
  ut.blockEvidencePhotos = photos;
  ut.blockedAt = new Date();
  ut.adminAction = undefined;
  ut.adminActionAt = undefined;
  ut.adminActionBy = undefined;
  ut.adminReviewNote = undefined;

  const updatedUt = await ut.save();

  io.emit('updatedUserTask', {
    id: updatedUt._id.toString(),
    userId: updatedUt.userId.toString(),
    taskId: updatedUt.taskId.toString(),
    status: updatedUt.status,
    blockStatus: updatedUt.blockStatus,
    blockReasonCategory: updatedUt.blockReasonCategory,
    blockReasonText: updatedUt.blockReasonText,
    blockEvidencePhotos: updatedUt.blockEvidencePhotos,
    blockedAt: updatedUt.blockedAt ? updatedUt.blockedAt.toISOString() : null,
    adminReviewNote: updatedUt.adminReviewNote,
    adminAction: updatedUt.adminAction,
    adminActionAt: updatedUt.adminActionAt ? updatedUt.adminActionAt.toISOString() : null,
  });

  setImmediate(async () => {
    try {
      const who = [
        (req.user?.name || '').toString().trim(),
        (req.user?.employeeId || '').toString().trim(),
      ].filter(Boolean);
      const whoLabel = who.join(' • ');
      const msg =
        whoLabel.length > 0
          ? `${whoLabel} blocked: ${task.title}`
          : `Task blocked: ${task.title}`;
      const payload = {
        taskId: String(task._id),
        userTaskId: String(updatedUt._id),
        employeeId: (req.user?.employeeId || '').toString(),
        employeeName: (req.user?.name || '').toString(),
        userId: String(req.user?._id || ''),
        reasonCategory: String(updatedUt.blockReasonCategory || ''),
        reasonText: String(updatedUt.blockReasonText || ''),
        blockedAt: updatedUt.blockedAt ? updatedUt.blockedAt.toISOString() : null,
        destination: 'tasks.blocked',
      };

      await appNotificationService.createForAdmins({
        excludeUserId: req.user?._id,
        type: 'task',
        action: 'task_blocked',
        title: 'Task Blocked',
        message: msg,
        payload,
      });

      const admins = await User.find({ role: 'admin', isActive: { $ne: false } }).select(
        '_id',
      );
      for (const admin of admins) {
        if (req.user?._id && String(admin._id) === String(req.user._id)) continue;
        try {
          await appNotificationService.createNotification({
            recipientUserId: admin._id,
            scope: 'messages',
            type: 'info',
            action: 'task_blocked',
            title: whoLabel.isNotEmpty ? whoLabel : 'Task blocked',
            message: msg,
            payload,
          });
        } catch (_) {}
      }
    } catch (_) {}
  });

  // Return task JSON augmented with assignment-specific status.
  res.json({
    ...toTaskJson(task, updatedUt._id.toString()),
    userTaskStatus: updatedUt.status,
    blockStatus: updatedUt.blockStatus,
    blockReasonCategory: updatedUt.blockReasonCategory,
    blockReasonText: updatedUt.blockReasonText,
    blockEvidencePhotos: updatedUt.blockEvidencePhotos,
    blockedAt: updatedUt.blockedAt ? updatedUt.blockedAt.toISOString() : null,
    adminReviewNote: updatedUt.adminReviewNote,
    adminAction: updatedUt.adminAction,
    adminActionAt: updatedUt.adminActionAt ? updatedUt.adminActionAt.toISOString() : null,
  });
});

// @desc Admin action: unblock a blocked task assignment (UserTask)
// @route PUT /api/tasks/user-task/:userTaskId/unblock
// @access Private/Admin
const unblockUserTask = asyncHandler(async (req, res) => {
  const { userTaskId } = req.params;
  const { adminReviewNote } = req.body;

  const note = (adminReviewNote ?? '').toString().trim();
  if (!note) {
    res.status(400);
    throw new Error('adminReviewNote is required');
  }

  const ut = await UserTask.findById(userTaskId);
  if (!ut) {
    res.status(404);
    throw new Error('UserTask not found');
  }

  const current = normalizeTaskStatus(ut.status);
  if (isTerminalTaskStatus(current)) {
    res.status(400);
    throw new Error('Completed tasks cannot be modified');
  }

  if (!isBlockedAssignment(ut)) {
    res.status(400);
    throw new Error('Only blocked assignments can be unblocked');
  }

  ut.blockStatus = 'unblocked';
  ut.adminReviewNote = note;
  ut.adminAction = 'unblocked';
  ut.adminActionAt = new Date();
  ut.adminActionBy = req.user?._id;

  const p = typeof ut.progressPercent === 'number' ? ut.progressPercent : 0;
  ut.status = p > 0 ? 'in_progress' : 'accepted';

  const updatedUt = await ut.save();

  io.emit('updatedUserTask', {
    id: updatedUt._id.toString(),
    userId: updatedUt.userId.toString(),
    taskId: updatedUt.taskId.toString(),
    status: updatedUt.status,
    blockStatus: updatedUt.blockStatus,
    blockReasonCategory: updatedUt.blockReasonCategory,
    blockReasonText: updatedUt.blockReasonText,
    blockEvidencePhotos: updatedUt.blockEvidencePhotos,
    blockedAt: updatedUt.blockedAt ? updatedUt.blockedAt.toISOString() : null,
    adminReviewNote: updatedUt.adminReviewNote,
    adminAction: updatedUt.adminAction,
    adminActionAt: updatedUt.adminActionAt ? updatedUt.adminActionAt.toISOString() : null,
    adminActionBy: updatedUt.adminActionBy ? updatedUt.adminActionBy.toString() : null,
  });

  res.status(200).json({
    id: updatedUt._id.toString(),
    userId: updatedUt.userId.toString(),
    taskId: updatedUt.taskId.toString(),
    status: updatedUt.status,
    blockStatus: updatedUt.blockStatus,
    blockedAt: updatedUt.blockedAt ? updatedUt.blockedAt.toISOString() : null,
    adminReviewNote: updatedUt.adminReviewNote,
    adminAction: updatedUt.adminAction,
    adminActionAt: updatedUt.adminActionAt ? updatedUt.adminActionAt.toISOString() : null,
  });
});

// @desc Admin action: close a blocked task assignment (UserTask)
// @route PUT /api/tasks/user-task/:userTaskId/close
// @access Private/Admin
const closeUserTask = asyncHandler(async (req, res) => {
  const { userTaskId } = req.params;
  const { adminReviewNote } = req.body;

  const note = (adminReviewNote ?? '').toString().trim();
  if (!note) {
    res.status(400);
    throw new Error('adminReviewNote is required');
  }

  const ut = await UserTask.findById(userTaskId);
  if (!ut) {
    res.status(404);
    throw new Error('UserTask not found');
  }

  const current = normalizeTaskStatus(ut.status);
  if (isTerminalTaskStatus(current)) {
    res.status(400);
    throw new Error('Completed tasks cannot be modified');
  }

  if (!isBlockedAssignment(ut)) {
    res.status(400);
    throw new Error('Only blocked assignments can be closed');
  }

  ut.status = 'closed';
  ut.blockStatus = 'closed';
  ut.adminReviewNote = note;
  ut.adminAction = 'closed';
  ut.adminActionAt = new Date();
  ut.adminActionBy = req.user?._id;

  const updatedUt = await ut.save();

  io.emit('updatedUserTask', {
    id: updatedUt._id.toString(),
    userId: updatedUt.userId.toString(),
    taskId: updatedUt.taskId.toString(),
    status: updatedUt.status,
    blockStatus: updatedUt.blockStatus,
    blockReasonCategory: updatedUt.blockReasonCategory,
    blockReasonText: updatedUt.blockReasonText,
    blockEvidencePhotos: updatedUt.blockEvidencePhotos,
    blockedAt: updatedUt.blockedAt ? updatedUt.blockedAt.toISOString() : null,
    adminReviewNote: updatedUt.adminReviewNote,
    adminAction: updatedUt.adminAction,
    adminActionAt: updatedUt.adminActionAt ? updatedUt.adminActionAt.toISOString() : null,
    adminActionBy: updatedUt.adminActionBy ? updatedUt.adminActionBy.toString() : null,
  });

  res.status(200).json({
    id: updatedUt._id.toString(),
    userId: updatedUt.userId.toString(),
    taskId: updatedUt.taskId.toString(),
    status: updatedUt.status,
    blockStatus: updatedUt.blockStatus,
    blockedAt: updatedUt.blockedAt ? updatedUt.blockedAt.toISOString() : null,
    adminReviewNote: updatedUt.adminReviewNote,
    adminAction: updatedUt.adminAction,
    adminActionAt: updatedUt.adminActionAt ? updatedUt.adminActionAt.toISOString() : null,
  });
});

// --- Missing function stubs (were exported but never defined) ---

const unassignTaskFromUser = asyncHandler(async (req, res) => {
  const { taskId, userId } = req.params;
  const ut = await UserTask.findOne({ taskId, userId, isArchived: { $ne: true } });
  if (!ut) {
    res.status(404);
    throw new Error('Assignment not found');
  }
  ut.isArchived = true;
  await ut.save();

  // Update active task count
  try {
    const count = await UserTask.countDocuments({
      userId, isArchived: { $ne: true }, status: { $ne: 'completed' },
    });
    await User.findByIdAndUpdate(userId, { activeTaskCount: count });
  } catch (_) {}

  io.emit('taskUnassigned', { taskId, userId });
  res.json({ message: 'Task unassigned', taskId, userId });
});

const markUserTaskViewed = asyncHandler(async (req, res) => {
  const { userTaskId } = req.params;
  const ut = await UserTask.findById(userTaskId);
  if (!ut) {
    res.status(404);
    throw new Error('UserTask not found');
  }
  ut.lastViewedAt = new Date();
  await ut.save();
  res.json({ id: ut._id.toString(), lastViewedAt: ut.lastViewedAt });
});

const archiveUserTask = asyncHandler(async (req, res) => {
  const { userTaskId } = req.params;
  const ut = await UserTask.findById(userTaskId);
  if (!ut) {
    res.status(404);
    throw new Error('UserTask not found');
  }
  ut.isArchived = true;
  await ut.save();
  io.emit('userTaskArchived', {
    id: ut._id.toString(),
    userId: ut.userId.toString(),
    taskId: ut.taskId.toString(),
  });
  res.json({ message: 'UserTask archived', id: ut._id.toString() });
});

const restoreUserTask = asyncHandler(async (req, res) => {
  const { userTaskId } = req.params;
  const ut = await UserTask.findById(userTaskId);
  if (!ut) {
    res.status(404);
    throw new Error('UserTask not found');
  }
  ut.isArchived = false;
  await ut.save();
  io.emit('userTaskRestored', {
    id: ut._id.toString(),
    userId: ut.userId.toString(),
    taskId: ut.taskId.toString(),
  });
  res.json({ message: 'UserTask restored', id: ut._id.toString() });
});

const escalateTask = asyncHandler(async (req, res) => {
  const task = await Task.findById(req.params.id);
  if (!task) { res.status(404); throw new Error('Task not found'); }
  // Mark difficulty as hard and notify admins
  task.difficulty = 'hard';
  await task.save();
  try {
    await appNotificationService.createForAdmins({
      type: 'task', action: 'escalated',
      title: 'Task Escalated',
      message: `Task "${task.title}" has been escalated.`,
      payload: { taskId: String(task._id) },
    });
  } catch (_) {}
  io.emit('updatedTask', toTaskJson(task));
  res.json(toTaskJson(task));
});

const gradeUserTask = asyncHandler(async (req, res) => {
  const { userTaskId } = req.params;
  const { score, feedback } = req.body;
  const ut = await UserTask.findById(userTaskId);
  if (!ut) { res.status(404); throw new Error('UserTask not found'); }
  ut.grade = {
    score: typeof score === 'number' ? Math.min(100, Math.max(0, score)) : undefined,
    feedback: feedback || '',
    gradedAt: new Date(),
    gradedBy: req.user._id,
  };
  if (ut.status !== 'closed') ut.status = 'reviewed';
  await ut.save();
  io.emit('updatedUserTaskStatus', {
    id: ut._id.toString(), userId: ut.userId.toString(),
    taskId: ut.taskId.toString(), status: ut.status,
  });
  // Notify the employee
  try {
    await appNotificationService.createNotification({
      recipientUserId: ut.userId,
      scope: 'tasks', type: 'info', action: 'task_graded',
      title: 'Task Graded',
      message: `Your task was graded: ${score}/100`,
      payload: { userTaskId: String(ut._id), score },
    });
  } catch (_) {}
  res.json({
    id: ut._id.toString(), grade: ut.grade, status: ut.status,
  });
});

const addCommentToUserTask = asyncHandler(async (req, res) => {
  const { userTaskId } = req.params;
  const { body: commentBody } = req.body;
  if (!commentBody || !commentBody.trim()) {
    res.status(400); throw new Error('Comment body is required');
  }
  const ut = await UserTask.findById(userTaskId);
  if (!ut) { res.status(404); throw new Error('UserTask not found'); }
  const comment = {
    sender: req.user._id,
    senderName: req.user.name || 'Unknown',
    body: commentBody.trim(),
    createdAt: new Date(),
  };
  ut.comments.push(comment);
  await ut.save();
  const saved = ut.comments[ut.comments.length - 1];
  io.emit('taskCommentAdded', {
    userTaskId: ut._id.toString(),
    taskId: ut.taskId.toString(),
    comment: {
      _id: saved._id.toString(),
      sender: String(req.user._id),
      senderName: req.user.name || 'Unknown',
      body: saved.body,
      createdAt: saved.createdAt.toISOString(),
    },
  });
  res.status(201).json(saved);
});

module.exports = {
  getTask,
  getTasks,
  getCurrentTasks,
  getArchivedTasks,
  getOverdueTasks,
  getTaskAssignees,
  createTask,
  updateTask,
  deleteTask,
  getUserTasks,
  getAssignedTasks,
  assignTaskToUser,
  assignTaskToMultipleUsers,
  unassignTaskFromUser,
  updateUserTaskStatus,
  acceptUserTask,
  markUserTaskViewed,
  updateTaskChecklistItem,
  blockTask,
  unblockUserTask,
  closeUserTask,
  archiveUserTask,
  restoreUserTask,
  archiveTask,
  restoreTask,
  escalateTask,
  gradeUserTask,
  addCommentToUserTask,
  cancelUserTask,
};