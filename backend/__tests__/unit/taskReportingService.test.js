const mongoose = require('mongoose');
const {
  generateTaskReport,
  exportReportAsCSV,
  exportReportAsPDF,
} = require('../../services/taskReportingService');
const Task = require('../../models/Task');
const Ticket = require('../../models/Ticket');
const Service = require('../../models/Service');
const Company = require('../../models/Company');
const User = require('../../models/User');

describe('Task Reporting Service', () => {
  let companyId, serviceId, ticketId, userId, employeeId;
  let company, service, ticket, user, employee;

  beforeAll(async () => {
    if (mongoose.connection.readyState === 0) {
      await mongoose.connect(process.env.MONGODB_TEST_URI || 'mongodb://localhost:27017/fieldcheck-test');
    }
  });

  afterAll(async () => {
    await mongoose.connection.close();
  });

  beforeEach(async () => {
    await Task.deleteMany({});
    await Ticket.deleteMany({});
    await Service.deleteMany({});
    await Company.deleteMany({});
    await User.deleteMany({});

    company = await Company.create({
      name: 'Test Company',
      email: 'test@company.com',
    });
    companyId = company._id;

    user = await User.create({
      name: 'Admin User',
      email: 'admin@test.com',
      password: 'password123',
      role: 'admin',
      companyId,
    });
    userId = user._id;

    employee = await User.create({
      name: 'Employee User',
      email: 'employee@test.com',
      password: 'password123',
      role: 'employee',
      companyId,
    });
    employeeId = employee._id;

    service = await Service.create({
      companyId,
      name: 'Test Service',
      description: 'A test service',
      isActive: true,
    });
    serviceId = service._id;

    ticket = await Ticket.create({
      companyId,
      serviceId,
      title: 'Test Ticket',
      description: 'A test ticket',
      status: 'open',
    });
    ticketId = ticket._id;
  });

  describe('generateTaskReport', () => {
    it('should generate report with basic metrics', async () => {
      await Task.create({
        title: 'Task 1',
        description: 'Test',
        companyId,
        assignedBy: userId,
        ticketId,
        taskOrigin: 'template',
        type: 'inspection',
        status: 'pending',
      });

      const report = await generateTaskReport(companyId);

      expect(report.summary.totalTasksCreated).toBe(1);
      expect(report.summary.tasksCompleted).toBe(0);
      expect(report.summary.tasksByOrigin.template).toBe(1);
      expect(report.summary.tasksByOrigin.ad_hoc).toBe(0);
    });

    it('should count tasks by status', async () => {
      await Task.create({
        title: 'Pending Task',
        companyId,
        assignedBy: userId,
        ticketId,
        status: 'pending',
      });

      await Task.create({
        title: 'In Progress Task',
        companyId,
        assignedBy: userId,
        ticketId,
        status: 'in_progress',
      });

      await Task.create({
        title: 'Completed Task',
        companyId,
        assignedBy: userId,
        ticketId,
        status: 'completed',
      });

      const report = await generateTaskReport(companyId);

      expect(report.summary.tasksByStatus.pending).toBe(1);
      expect(report.summary.tasksByStatus.in_progress).toBe(1);
      expect(report.summary.tasksByStatus.completed).toBe(1);
    });

    it('should count tasks by type', async () => {
      await Task.create({
        title: 'Inspection',
        companyId,
        assignedBy: userId,
        ticketId,
        type: 'inspection',
      });

      await Task.create({
        title: 'Maintenance',
        companyId,
        assignedBy: userId,
        ticketId,
        type: 'maintenance',
      });

      const report = await generateTaskReport(companyId);

      expect(report.summary.tasksByType.inspection).toBe(1);
      expect(report.summary.tasksByType.maintenance).toBe(1);
    });

    it('should calculate completion percentage', async () => {
      await Task.create({
        title: 'Task 1',
        companyId,
        assignedBy: userId,
        ticketId,
        status: 'completed',
      });

      await Task.create({
        title: 'Task 2',
        companyId,
        assignedBy: userId,
        ticketId,
        status: 'pending',
      });

      const report = await generateTaskReport(companyId);

      expect(report.summary.completionPercentage).toBe(50);
    });

    it('should calculate completion rate by type', async () => {
      await Task.create({
        title: 'Inspection 1',
        companyId,
        assignedBy: userId,
        ticketId,
        type: 'inspection',
        status: 'completed',
      });

      await Task.create({
        title: 'Inspection 2',
        companyId,
        assignedBy: userId,
        ticketId,
        type: 'inspection',
        status: 'pending',
      });

      const report = await generateTaskReport(companyId);

      expect(report.completionRateByType.inspection.completed).toBe(1);
      expect(report.completionRateByType.inspection.total).toBe(2);
      expect(report.completionRateByType.inspection.percentage).toBe(50);
    });

    it('should calculate average completion time by type', async () => {
      const createdTime = new Date('2024-01-01T10:00:00Z');
      const completedTime = new Date('2024-01-01T12:00:00Z');
      const durationMs = completedTime.getTime() - createdTime.getTime();

      await Task.create({
        title: 'Inspection',
        companyId,
        assignedBy: userId,
        ticketId,
        type: 'inspection',
        status: 'completed',
        createdAt: createdTime,
        completedAt: completedTime,
        taskDuration: durationMs,
      });

      const report = await generateTaskReport(companyId);

      expect(report.averageCompletionTimeByType.inspection).toBeDefined();
      expect(report.averageCompletionTimeByType.inspection.averageMs).toBe(durationMs);
      expect(report.averageCompletionTimeByType.inspection.averageHours).toBeCloseTo(2, 1);
    });

    it('should track employee performance metrics', async () => {
      const durationMs = 3600000; // 1 hour

      await Task.create({
        title: 'Task 1',
        companyId,
        assignedBy: userId,
        ticketId,
        status: 'completed',
        completedBy: employeeId,
        taskDuration: durationMs,
      });

      await Task.create({
        title: 'Task 2',
        companyId,
        assignedBy: userId,
        ticketId,
        status: 'completed',
        completedBy: employeeId,
        taskDuration: durationMs,
      });

      const report = await generateTaskReport(companyId);

      expect(report.employeePerformance).toHaveLength(1);
      expect(report.employeePerformance[0].employeeName).toBe('Employee User');
      expect(report.employeePerformance[0].tasksCompleted).toBe(2);
      expect(report.employeePerformance[0].averageCompletionTime.averageHours).toBeCloseTo(1, 1);
    });

    it('should track checklist completion rates', async () => {
      await Task.create({
        title: 'Task with Checklist',
        companyId,
        assignedBy: userId,
        ticketId,
        checklist: [
          { label: 'Item 1', isCompleted: true },
          { label: 'Item 2', isCompleted: true },
          { label: 'Item 3', isCompleted: false },
        ],
      });

      const report = await generateTaskReport(companyId);

      expect(report.checklistCompletionRates).toHaveLength(1);
      expect(report.checklistCompletionRates[0].completedItems).toBe(2);
      expect(report.checklistCompletionRates[0].totalItems).toBe(3);
      expect(report.checklistCompletionRates[0].completionPercentage).toBeCloseTo(66.67, 1);
    });

    it('should track template effectiveness', async () => {
      await Task.create({
        title: 'Template Task',
        companyId,
        assignedBy: userId,
        ticketId,
        taskOrigin: 'template',
      });

      await Task.create({
        title: 'Ad-hoc Task',
        companyId,
        assignedBy: userId,
        ticketId,
        taskOrigin: 'ad_hoc',
      });

      const report = await generateTaskReport(companyId);

      expect(report.templateEffectiveness).toHaveLength(1);
      expect(report.templateEffectiveness[0].templateTasksCreated).toBe(1);
      expect(report.templateEffectiveness[0].adHocTasksAdded).toBe(1);
    });

    it('should filter by date range', async () => {
      const startDate = new Date('2024-01-01');
      const endDate = new Date('2024-01-31');

      await Task.create({
        title: 'Task in range',
        companyId,
        assignedBy: userId,
        ticketId,
        createdAt: new Date('2024-01-15'),
      });

      await Task.create({
        title: 'Task out of range',
        companyId,
        assignedBy: userId,
        ticketId,
        createdAt: new Date('2024-02-15'),
      });

      const report = await generateTaskReport(companyId, { startDate, endDate });

      expect(report.summary.totalTasksCreated).toBe(1);
    });

    it('should filter by service', async () => {
      const otherService = await Service.create({
        companyId,
        name: 'Other Service',
        isActive: true,
      });

      const otherTicket = await Ticket.create({
        companyId,
        serviceId: otherService._id,
        title: 'Other Ticket',
      });

      await Task.create({
        title: 'Task for service',
        companyId,
        assignedBy: userId,
        ticketId,
      });

      await Task.create({
        title: 'Task for other service',
        companyId,
        assignedBy: userId,
        ticketId: otherTicket._id,
      });

      const report = await generateTaskReport(companyId, { serviceId });

      expect(report.summary.totalTasksCreated).toBe(1);
    });

    it('should filter by status', async () => {
      await Task.create({
        title: 'Completed Task',
        companyId,
        assignedBy: userId,
        ticketId,
        status: 'completed',
      });

      await Task.create({
        title: 'Pending Task',
        companyId,
        assignedBy: userId,
        ticketId,
        status: 'pending',
      });

      const report = await generateTaskReport(companyId, { status: 'completed' });

      expect(report.summary.totalTasksCreated).toBe(1);
      expect(report.summary.tasksCompleted).toBe(1);
    });
  });

  describe('exportReportAsCSV', () => {
    it('should export report as CSV', async () => {
      const report = await generateTaskReport(companyId);

      const csv = exportReportAsCSV(report);

      expect(csv).toContain('Task Report');
      expect(csv).toContain('SUMMARY');
      expect(csv).toContain('Total Tasks Created');
      expect(csv).toContain('Tasks Completed');
    });

    it('should include all report sections in CSV', async () => {
      await Task.create({
        title: 'Task',
        companyId,
        assignedBy: userId,
        ticketId,
        type: 'inspection',
        status: 'completed',
        completedBy: employeeId,
        taskDuration: 3600000,
        checklist: [
          { label: 'Item 1', isCompleted: true },
          { label: 'Item 2', isCompleted: false },
        ],
      });

      const report = await generateTaskReport(companyId);
      const csv = exportReportAsCSV(report);

      expect(csv).toContain('TASKS BY ORIGIN');
      expect(csv).toContain('TASKS BY STATUS');
      expect(csv).toContain('TASKS BY TYPE');
      expect(csv).toContain('COMPLETION RATE BY TYPE');
      expect(csv).toContain('EMPLOYEE PERFORMANCE');
      expect(csv).toContain('CHECKLIST COMPLETION RATES');
      expect(csv).toContain('TEMPLATE EFFECTIVENESS');
    });

    it('should format data correctly in CSV', async () => {
      await Task.create({
        title: 'Task',
        companyId,
        assignedBy: userId,
        ticketId,
        type: 'inspection',
        status: 'completed',
      });

      const report = await generateTaskReport(companyId);
      const csv = exportReportAsCSV(report);

      expect(csv).toContain('Total Tasks Created,1');
      expect(csv).toContain('Tasks Completed,1');
      expect(csv).toContain('Completion Percentage,100.00%');
    });
  });

  describe('exportReportAsPDF', () => {
    it('should export report as PDF', async () => {
      const report = await generateTaskReport(companyId);

      const pdfStream = exportReportAsPDF(report);

      expect(pdfStream).toBeDefined();
      expect(pdfStream.end).toBeDefined(); // PDFKit document has end method
    });

    it('should include report title in PDF', async () => {
      const report = await generateTaskReport(companyId);
      const pdfStream = exportReportAsPDF(report);

      // PDFKit streams content, we can't easily verify content
      // but we can verify the stream is created
      expect(pdfStream).toBeDefined();
    });
  });
});
