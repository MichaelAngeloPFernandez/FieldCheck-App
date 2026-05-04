/**
 * Unit tests for Task Reporting Service
 * Tests the export functions without database
 */

const { exportReportAsCSV, exportReportAsPDF } = require('../../services/taskReportingService');

describe('Task Reporting Service - Export Functions', () => {
  const mockReport = {
    generatedAt: new Date('2024-01-15T10:00:00Z'),
    companyId: 'company123',
    filters: {},
    summary: {
      totalTasksCreated: 10,
      tasksCompleted: 7,
      completionPercentage: 70,
      tasksByOrigin: {
        template: 6,
        ad_hoc: 4,
      },
      tasksByStatus: {
        pending: 2,
        in_progress: 1,
        completed: 7,
      },
      tasksByType: {
        inspection: 5,
        maintenance: 5,
      },
    },
    completionRateByType: {
      inspection: {
        completed: 4,
        total: 5,
        percentage: 80,
      },
      maintenance: {
        completed: 3,
        total: 5,
        percentage: 60,
      },
    },
    averageCompletionTimeByType: {
      inspection: {
        averageMs: 3600000,
        averageHours: 1,
        averageDays: 0.042,
      },
      maintenance: {
        averageMs: 7200000,
        averageHours: 2,
        averageDays: 0.083,
      },
    },
    completionRateByService: {},
    employeePerformance: [
      {
        employeeId: 'emp1',
        employeeName: 'John Doe',
        employeeEmail: 'john@example.com',
        tasksCompleted: 5,
        totalCompletionTime: 18000000,
        averageCompletionTime: {
          averageMs: 3600000,
          averageHours: 1,
          averageDays: 0.042,
        },
      },
      {
        employeeId: 'emp2',
        employeeName: 'Jane Smith',
        employeeEmail: 'jane@example.com',
        tasksCompleted: 2,
        totalCompletionTime: 14400000,
        averageCompletionTime: {
          averageMs: 7200000,
          averageHours: 2,
          averageDays: 0.083,
        },
      },
    ],
    checklistCompletionRates: [
      {
        taskId: 'task1',
        taskTitle: 'Inspection Task',
        completedItems: 3,
        totalItems: 4,
        completionPercentage: 75,
      },
    ],
    templateEffectiveness: [
      {
        serviceId: 'service1',
        templateTasksCreated: 6,
        adHocTasksAdded: 4,
      },
    ],
  };

  describe('exportReportAsCSV', () => {
    it('should export report as CSV string', () => {
      const csv = exportReportAsCSV(mockReport);

      expect(typeof csv).toBe('string');
      expect(csv.length).toBeGreaterThan(0);
    });

    it('should include report title', () => {
      const csv = exportReportAsCSV(mockReport);

      expect(csv).toContain('Task Report');
    });

    it('should include summary section', () => {
      const csv = exportReportAsCSV(mockReport);

      expect(csv).toContain('SUMMARY');
      expect(csv).toContain('Total Tasks Created,10');
      expect(csv).toContain('Tasks Completed,7');
      expect(csv).toContain('Completion Percentage,70.00%');
    });

    it('should include tasks by origin', () => {
      const csv = exportReportAsCSV(mockReport);

      expect(csv).toContain('TASKS BY ORIGIN');
      expect(csv).toContain('Template Tasks,6');
      expect(csv).toContain('Ad-hoc Tasks,4');
    });

    it('should include tasks by status', () => {
      const csv = exportReportAsCSV(mockReport);

      expect(csv).toContain('TASKS BY STATUS');
      expect(csv).toContain('pending,2');
      expect(csv).toContain('in_progress,1');
      expect(csv).toContain('completed,7');
    });

    it('should include tasks by type', () => {
      const csv = exportReportAsCSV(mockReport);

      expect(csv).toContain('TASKS BY TYPE');
      expect(csv).toContain('inspection,5');
      expect(csv).toContain('maintenance,5');
    });

    it('should include completion rate by type', () => {
      const csv = exportReportAsCSV(mockReport);

      expect(csv).toContain('COMPLETION RATE BY TYPE');
      expect(csv).toContain('inspection,4,5,80.00%');
      expect(csv).toContain('maintenance,3,5,60.00%');
    });

    it('should include average completion time by type', () => {
      const csv = exportReportAsCSV(mockReport);

      expect(csv).toContain('AVERAGE COMPLETION TIME BY TYPE');
      expect(csv).toContain('inspection');
      expect(csv).toContain('maintenance');
    });

    it('should include employee performance', () => {
      const csv = exportReportAsCSV(mockReport);

      expect(csv).toContain('EMPLOYEE PERFORMANCE');
      expect(csv).toContain('John Doe');
      expect(csv).toContain('jane@example.com');
      expect(csv).toContain('5');
      expect(csv).toContain('2');
    });

    it('should include checklist completion rates', () => {
      const csv = exportReportAsCSV(mockReport);

      expect(csv).toContain('CHECKLIST COMPLETION RATES');
      expect(csv).toContain('Inspection Task');
      expect(csv).toContain('3,4,75.00%');
    });

    it('should include template effectiveness', () => {
      const csv = exportReportAsCSV(mockReport);

      expect(csv).toContain('TEMPLATE EFFECTIVENESS');
      expect(csv).toContain('6');
      expect(csv).toContain('4');
    });

    it('should handle empty employee performance', () => {
      const reportWithoutEmployees = { ...mockReport, employeePerformance: [] };

      const csv = exportReportAsCSV(reportWithoutEmployees);

      expect(csv).toContain('EMPLOYEE PERFORMANCE');
    });

    it('should handle empty checklist completion rates', () => {
      const reportWithoutChecklists = { ...mockReport, checklistCompletionRates: [] };

      const csv = exportReportAsCSV(reportWithoutChecklists);

      expect(typeof csv).toBe('string');
    });
  });

  describe('exportReportAsPDF', () => {
    it('should export report as PDF stream', () => {
      const pdfStream = exportReportAsPDF(mockReport);

      expect(pdfStream).toBeDefined();
      expect(typeof pdfStream.end).toBe('function');
    });

    it('should return a stream object', () => {
      const pdfStream = exportReportAsPDF(mockReport);

      expect(pdfStream).toBeDefined();
      expect(typeof pdfStream.on).toBe('function');
      expect(typeof pdfStream.pipe).toBe('function');
    });

    it('should handle report with various data', () => {
      const pdfStream = exportReportAsPDF(mockReport);

      expect(pdfStream).toBeDefined();
    });

    it('should handle empty employee performance', () => {
      const reportWithoutEmployees = { ...mockReport, employeePerformance: [] };

      const pdfStream = exportReportAsPDF(reportWithoutEmployees);

      expect(pdfStream).toBeDefined();
    });
  });
});
