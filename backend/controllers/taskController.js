const asyncHandler = require('express-async-handler');
const Task = require('../models/Task');
const UserTask = require('../models/UserTask');
const User = require('../models/User');
const { io } = require('../server');
const Report = require('../models/Report');

// Map Task mongoose doc to Flutter-friendly shape
function toTaskJson(doc, userTaskId) {
  return {
    id: doc._id.toString(),
    title: doc.title,
    description: doc.description || '',
    dueDate: doc.dueDate ? doc.dueDate.toISOString() : new Date().toISOString(),
    assignedBy: doc.assignedBy?.toString() || '',
    createdAt: doc.createdAt?.toISOString() || new Date().toISOString(),
    status: doc.status || 'pending',
    userTaskId: userTaskId || undefined,
    geofenceId: doc.geofenceId?.toString() || undefined,
    latitude: doc.latitude,
    longitude: doc.longitude,
  };
}

// @route GET /api/tasks
// @access Private (admin or employee)
const getTasks = asyncHandler(async (req, res) => {
  const tasks = await Task.find({}).sort({ createdAt: -1 });
  res.json(tasks.map((t) => toTaskJson(t)));
});

// @route POST /api/tasks
// @access Private/Admin
const createTask = asyncHandler(async (req, res) => {
  const { title, description, dueDate, status, geofenceId } = req.body;
  if (!title) {
    res.status(400);
    throw new Error('Title is required');
  }
  const taskData = {
    title,
    description: description || '',
    dueDate: dueDate ? new Date(dueDate) : undefined,
    assignedBy: req.user._id,
    status: status || 'pending',
    geofenceId: geofenceId || undefined,
  };
  const task = await Task.create(taskData);
  io.emit('newTask', toTaskJson(task)); // Emit real-time event
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
  // Only update if values are explicitly provided (not undefined)
  if (req.body.title !== undefined) task.title = req.body.title;
  if (req.body.description !== undefined) task.description = req.body.description;
  if (req.body.status !== undefined) task.status = req.body.status;
  if (req.body.geofenceId !== undefined) task.geofenceId = req.body.geofenceId;
  if (req.body.dueDate !== undefined) task.dueDate = new Date(req.body.dueDate);
  
  const updated = await task.save();
  io.emit('updatedTask', toTaskJson(updated));
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
  const tasks = await Task.find({ _id: { $in: taskIds } });
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
  const ut = await UserTask.create({ taskId, userId });
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
  if (!userIds.every(id => typeof id === 'string' && id.trim() !== '')) {
    res.status(400);
    throw new Error('All user IDs must be non-empty strings');
  }

  const task = await Task.findById(taskId);
  if (!task) {
    res.status(404);
    throw new Error('Task not found');
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
        const ut = await UserTask.create({ taskId, userId });
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
    io.emit('taskAssignedToMultiple', { taskId, userIds: results.filter(r => r.success).map(r => r.userId) });
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
  const ut = await UserTask.findById(userTaskId);
  if (!ut) {
    res.status(404);
    throw new Error('UserTask not found');
  }
  ut.status = status;
  if (status === 'completed') {
    ut.completedAt = new Date();
  } else if (!status || status === 'pending') {
    ut.completedAt = undefined;
  }
  await ut.save();
  
  // IMPORTANT: Also update the Task status so frontend sees the change
  try {
    const Task = require('../models/Task');
    await Task.findByIdAndUpdate(ut.taskId, { status: status }, { new: true });
    console.log(`✓ Updated Task ${ut.taskId} status to ${status}`);
  } catch (e) {
    console.warn(`⚠️ Failed to update Task status: ${e.message}`);
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
  res.json({
    id: ut._id.toString(),
    userId: ut.userId.toString(),
    taskId: ut.taskId.toString(),
    status: ut.status,
    assignedAt: ut.assignedAt.toISOString(),
    completedAt: ut.completedAt ? ut.completedAt.toISOString() : null,
  });
});

module.exports = {
  getTasks,
  createTask,
  updateTask,
  deleteTask,
  getUserTasks,
  getAssignedTasks,
  assignTaskToUser,
  assignTaskToMultipleUsers,
  updateUserTaskStatus,
};