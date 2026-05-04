const Task = require('../models/Task');
const TaskTemplate = require('../models/TaskTemplate');
const Service = require('../models/Service');
const User = require('../models/User');
const ReportExportService = require('./reportExportService');

/**
 * Generate comprehensive task report with various metrics
 * @param {string} companyId - The company ID
 * @param {Object} filters - Filter options
 * @param {Date} filters.startDate - Start date for report
 * @param {Date} filters.endDate - End date for report
 * @param {string} filters.serviceId - Optional service ID filter
 * @param {string} filters.status - Optional status filter
 * @returns {Promise<Object>} Report object with metrics
 */
async function generateTaskReport(companyId, filters = {}) {
  const { startDate, endDate, serviceId, status } = filters;

  // Build query filter
  const query = { companyId };

  if (startDate || endDate) {
    query.createdAt = {};
    if (startDate) {
      query.createdAt.$gte = new Date(startDate);
    }
    if (endDate) {
      query.createdAt.$lte = new Date(endDate);
    }
  }

  if (serviceId) {
    // Get all tickets for this service to filter tasks
    const Ticket = require('../models/Ticket');
    const tickets = await Ticket.find({ serviceId, companyId }).select('_id');
    const ticketIds = tickets.map((t) => t._id);
    query.ticketId = { $in: ticketIds };
  }

  if (status) {
    query.status = status;
  }

  // Get all tasks matching filters
  const tasks = await Task.find(query)
    .populate('assignedTo', 'name email')
    .populate('completedBy', 'name email')
    .populate('templateId', 'title')
    .populate('ticketId', 'title serviceId');

  // Calculate metrics
  const report = {
    generatedAt: new Date(),
    companyId,
    filters,
    summary: {
      totalTasksCreated: tasks.length,
      tasksCompleted: 0,
      completionPercentage: 0,
      tasksByOrigin: {
        template: 0,
        ad_hoc: 0,
      },
      tasksByStatus: {},
      tasksByType: {},
    },
    completionRateByType: {},
    completionRateByService: {},
    averageCompletionTimeByType: {},
    employeePerformance: {},
    checklistCompletionRates: {},
    templateEffectiveness: {},
  };

  // Count tasks by status
  const statusCounts = {};
  const typeCounts = {};
  const typeCompletionCounts = {};
  const typeCompletionTimes = {};
  const serviceCounts = {};
  const serviceCompletionCounts = {};
  const serviceCompletionTimes = {};
  const employeeMetrics = {};
  const checklistMetrics = {};
  const templateMetrics = {};

  for (const task of tasks) {
    // Count by origin
    if (task.taskOrigin === 'template') {
      report.summary.tasksByOrigin.template++;
    } else {
      report.summary.tasksByOrigin.ad_hoc++;
    }

    // Count by status
    const taskStatus = task.status || 'pending';
    statusCounts[taskStatus] = (statusCounts[taskStatus] || 0) + 1;

    // Count by type
    const taskType = task.type || 'general';
    typeCounts[taskType] = (typeCounts[taskType] || 0) + 1;

    // Track completion metrics
    if (taskStatus === 'completed' || taskStatus === 'reviewed' || taskStatus === 'closed') {
      report.summary.tasksCompleted++;

      // Track completion by type
      typeCompletionCounts[taskType] = (typeCompletionCounts[taskType] || 0) + 1;

      // Track completion time by type
      if (task.taskDuration) {
        if (!typeCompletionTimes[taskType]) {
          typeCompletionTimes[taskType] = { total: 0, count: 0 };
        }
        typeCompletionTimes[taskType].total += task.taskDuration;
        typeCompletionTimes[taskType].count++;
      }

      // Track employee performance
      if (task.completedBy) {
        const employeeId = task.completedBy._id.toString();
        if (!employeeMetrics[employeeId]) {
          employeeMetrics[employeeId] = {
            employeeId,
            employeeName: task.completedBy.name,
            employeeEmail: task.completedBy.email,
            tasksCompleted: 0,
            totalCompletionTime: 0,
            averageCompletionTime: 0,
          };
        }
        employeeMetrics[employeeId].tasksCompleted++;
        if (task.taskDuration) {
          employeeMetrics[employeeId].totalCompletionTime += task.taskDuration;
        }
      }
    }

    // Track service metrics
    if (task.ticketId && task.ticketId.serviceId) {
      const serviceId = task.ticketId.serviceId.toString();
      serviceCounts[serviceId] = (serviceCounts[serviceId] || 0) + 1;

      if (taskStatus === 'completed' || taskStatus === 'reviewed' || taskStatus === 'closed') {
        serviceCompletionCounts[serviceId] = (serviceCompletionCounts[serviceId] || 0) + 1;

        if (task.taskDuration) {
          if (!serviceCompletionTimes[serviceId]) {
            serviceCompletionTimes[serviceId] = { total: 0, count: 0 };
          }
          serviceCompletionTimes[serviceId].total += task.taskDuration;
          serviceCompletionTimes[serviceId].count++;
        }
      }
    }

    // Track checklist completion
    if (task.checklist && task.checklist.length > 0) {
      const taskId = task._id.toString();
      const completedItems = task.checklist.filter((item) => item.isCompleted).length;
      const totalItems = task.checklist.length;
      checklistMetrics[taskId] = {
        taskId,
        taskTitle: task.title,
        completedItems,
        totalItems,
        completionPercentage: (completedItems / totalItems) * 100,
      };
    }

    // Track template effectiveness (ad-hoc tasks added per service)
    if (task.taskOrigin === 'ad_hoc' && task.ticketId && task.ticketId.serviceId) {
      const serviceId = task.ticketId.serviceId.toString();
      if (!templateMetrics[serviceId]) {
        templateMetrics[serviceId] = {
          serviceId,
          adHocTasksAdded: 0,
          templateTasksCreated: 0,
        };
      }
      templateMetrics[serviceId].adHocTasksAdded++;
    } else if (task.taskOrigin === 'template' && task.ticketId && task.ticketId.serviceId) {
      const serviceId = task.ticketId.serviceId.toString();
      if (!templateMetrics[serviceId]) {
        templateMetrics[serviceId] = {
          serviceId,
          adHocTasksAdded: 0,
          templateTasksCreated: 0,
        };
      }
      templateMetrics[serviceId].templateTasksCreated++;
    }
  }

  // Populate summary
  report.summary.tasksByStatus = statusCounts;
  report.summary.tasksByType = typeCounts;
  report.summary.completionPercentage =
    tasks.length > 0 ? (report.summary.tasksCompleted / tasks.length) * 100 : 0;

  // Calculate completion rate by type
  for (const type in typeCounts) {
    const completed = typeCompletionCounts[type] || 0;
    const total = typeCounts[type];
    report.completionRateByType[type] = {
      completed,
      total,
      percentage: (completed / total) * 100,
    };
  }

  // Calculate average completion time by type
  for (const type in typeCompletionTimes) {
    const { total, count } = typeCompletionTimes[type];
    const averageMs = total / count;
    report.averageCompletionTimeByType[type] = {
      averageMs,
      averageHours: averageMs / (1000 * 60 * 60),
      averageDays: averageMs / (1000 * 60 * 60 * 24),
    };
  }

  // Calculate completion rate by service
  for (const serviceId in serviceCounts) {
    const completed = serviceCompletionCounts[serviceId] || 0;
    const total = serviceCounts[serviceId];
    report.completionRateByService[serviceId] = {
      completed,
      total,
      percentage: (completed / total) * 100,
    };
  }

  // Calculate average completion time by service
  for (const serviceId in serviceCompletionTimes) {
    const { total, count } = serviceCompletionTimes[serviceId];
    const averageMs = total / count;
    report.completionRateByService[serviceId].averageCompletionTime = {
      averageMs,
      averageHours: averageMs / (1000 * 60 * 60),
      averageDays: averageMs / (1000 * 60 * 60 * 24),
    };
  }

  // Calculate employee performance metrics
  for (const employeeId in employeeMetrics) {
    const metric = employeeMetrics[employeeId];
    if (metric.tasksCompleted > 0) {
      metric.averageCompletionTime = {
        averageMs: metric.totalCompletionTime / metric.tasksCompleted,
        averageHours: metric.totalCompletionTime / metric.tasksCompleted / (1000 * 60 * 60),
        averageDays: metric.totalCompletionTime / metric.tasksCompleted / (1000 * 60 * 60 * 24),
      };
    }
  }
  report.employeePerformance = Object.values(employeeMetrics);

  // Add checklist completion rates
  report.checklistCompletionRates = Object.values(checklistMetrics);

  // Add template effectiveness
  report.templateEffectiveness = Object.values(templateMetrics);

  return report;
}

/**
 * Export report as CSV
 * @param {Object} report - The report object from generateTaskReport
 * @returns {string} CSV string
 */
function exportReportAsCSV(report) {
  let csv = 'Task Report\n';
  csv += `Generated: ${report.generatedAt.toLocaleString()}\n\n`;

  // Summary section
  csv += 'SUMMARY\n';
  csv += `Total Tasks Created,${report.summary.totalTasksCreated}\n`;
  csv += `Tasks Completed,${report.summary.tasksCompleted}\n`;
  csv += `Completion Percentage,${report.summary.completionPercentage.toFixed(2)}%\n\n`;

  // Tasks by origin
  csv += 'TASKS BY ORIGIN\n';
  csv += `Template Tasks,${report.summary.tasksByOrigin.template}\n`;
  csv += `Ad-hoc Tasks,${report.summary.tasksByOrigin.ad_hoc}\n\n`;

  // Tasks by status
  csv += 'TASKS BY STATUS\n';
  csv += 'Status,Count\n';
  for (const [status, count] of Object.entries(report.summary.tasksByStatus)) {
    csv += `${status},${count}\n`;
  }
  csv += '\n';

  // Tasks by type
  csv += 'TASKS BY TYPE\n';
  csv += 'Type,Count\n';
  for (const [type, count] of Object.entries(report.summary.tasksByType)) {
    csv += `${type},${count}\n`;
  }
  csv += '\n';

  // Completion rate by type
  csv += 'COMPLETION RATE BY TYPE\n';
  csv += 'Type,Completed,Total,Percentage\n';
  for (const [type, data] of Object.entries(report.completionRateByType)) {
    csv += `${type},${data.completed},${data.total},${data.percentage.toFixed(2)}%\n`;
  }
  csv += '\n';

  // Average completion time by type
  csv += 'AVERAGE COMPLETION TIME BY TYPE\n';
  csv += 'Type,Average Hours,Average Days\n';
  for (const [type, data] of Object.entries(report.averageCompletionTimeByType)) {
    csv += `${type},${data.averageHours.toFixed(2)},${data.averageDays.toFixed(2)}\n`;
  }
  csv += '\n';

  // Employee performance
  csv += 'EMPLOYEE PERFORMANCE\n';
  csv += 'Employee Name,Email,Tasks Completed,Average Hours,Average Days\n';
  for (const employee of report.employeePerformance) {
    const avgHours = employee.averageCompletionTime?.averageHours || 0;
    const avgDays = employee.averageCompletionTime?.averageDays || 0;
    csv += `${employee.employeeName},${employee.employeeEmail},${employee.tasksCompleted},${avgHours.toFixed(2)},${avgDays.toFixed(2)}\n`;
  }
  csv += '\n';

  // Checklist completion rates
  if (report.checklistCompletionRates.length > 0) {
    csv += 'CHECKLIST COMPLETION RATES\n';
    csv += 'Task Title,Completed Items,Total Items,Completion Percentage\n';
    for (const checklist of report.checklistCompletionRates) {
      csv += `${checklist.taskTitle},${checklist.completedItems},${checklist.totalItems},${checklist.completionPercentage.toFixed(2)}%\n`;
    }
    csv += '\n';
  }

  // Template effectiveness
  if (report.templateEffectiveness.length > 0) {
    csv += 'TEMPLATE EFFECTIVENESS\n';
    csv += 'Service ID,Template Tasks Created,Ad-hoc Tasks Added\n';
    for (const effectiveness of report.templateEffectiveness) {
      csv += `${effectiveness.serviceId},${effectiveness.templateTasksCreated},${effectiveness.adHocTasksAdded}\n`;
    }
  }

  return csv;
}

/**
 * Export report as PDF
 * @param {Object} report - The report object from generateTaskReport
 * @returns {Stream} PDF stream
 */
function exportReportAsPDF(report) {
  const PDFDocument = require('pdfkit');
  const doc = new PDFDocument({
    margin: 50,
    size: 'A4',
  });

  // Title
  doc.fontSize(20).font('Helvetica-Bold').text('Task Report', { align: 'center' });
  doc.moveDown(0.5);

  // Report metadata
  doc.fontSize(10).font('Helvetica');
  doc.text(`Generated: ${report.generatedAt.toLocaleString()}`, { align: 'center' });
  doc.moveDown(1);

  // Summary section
  doc.fontSize(14).font('Helvetica-Bold').text('Summary', 50);
  doc.fontSize(10).font('Helvetica');
  doc.text(`Total Tasks Created: ${report.summary.totalTasksCreated}`);
  doc.text(`Tasks Completed: ${report.summary.tasksCompleted}`);
  doc.text(`Completion Percentage: ${report.summary.completionPercentage.toFixed(2)}%`);
  doc.moveDown(0.5);

  // Tasks by origin
  doc.text(`Template Tasks: ${report.summary.tasksByOrigin.template}`);
  doc.text(`Ad-hoc Tasks: ${report.summary.tasksByOrigin.ad_hoc}`);
  doc.moveDown(1);

  // Tasks by status
  doc.fontSize(12).font('Helvetica-Bold').text('Tasks by Status');
  doc.fontSize(10).font('Helvetica');
  for (const [status, count] of Object.entries(report.summary.tasksByStatus)) {
    doc.text(`${status}: ${count}`);
  }
  doc.moveDown(1);

  // Tasks by type
  doc.fontSize(12).font('Helvetica-Bold').text('Tasks by Type');
  doc.fontSize(10).font('Helvetica');
  for (const [type, count] of Object.entries(report.summary.tasksByType)) {
    doc.text(`${type}: ${count}`);
  }
  doc.moveDown(1);

  // Completion rate by type
  doc.fontSize(12).font('Helvetica-Bold').text('Completion Rate by Type');
  doc.fontSize(10).font('Helvetica');
  for (const [type, data] of Object.entries(report.completionRateByType)) {
    doc.text(`${type}: ${data.completed}/${data.total} (${data.percentage.toFixed(2)}%)`);
  }
  doc.moveDown(1);

  // Employee performance
  if (report.employeePerformance.length > 0) {
    doc.fontSize(12).font('Helvetica-Bold').text('Employee Performance');
    doc.fontSize(10).font('Helvetica');
    for (const employee of report.employeePerformance) {
      const avgHours = employee.averageCompletionTime?.averageHours || 0;
      doc.text(
        `${employee.employeeName}: ${employee.tasksCompleted} tasks completed (avg ${avgHours.toFixed(2)} hours)`
      );
    }
    doc.moveDown(1);
  }

  // Footer
  doc.fontSize(8).font('Helvetica');
  doc.text('FieldCheck - Task Report', 50, doc.page.height - 30, { align: 'center' });

  doc.end();
  return doc;
}

module.exports = {
  generateTaskReport,
  exportReportAsCSV,
  exportReportAsPDF,
};
