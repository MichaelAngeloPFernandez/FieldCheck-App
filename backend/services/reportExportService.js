const PDFDocument = require('pdfkit');
const ExcelJS = require('exceljs');
const { Readable } = require('stream');

class ReportExportService {
  /**
   * Generate PDF report for attendance records
   * @param {Array} records - Attendance records
   * @param {Object} options - Export options (title, dateRange, etc.)
   * @returns {Stream} PDF stream
   */
  static generateAttendancePDF(records, options = {}) {
    const doc = new PDFDocument({
      margin: 50,
      size: 'A4',
    });

    // Title
    doc.fontSize(20).font('Helvetica-Bold').text('Attendance Report', { align: 'center' });
    doc.moveDown(0.5);

    // Report metadata
    doc.fontSize(10).font('Helvetica');
    doc.text(`Generated: ${new Date().toLocaleString()}`, { align: 'center' });
    if (options.dateRange) {
      doc.text(`Period: ${options.dateRange}`, { align: 'center' });
    }
    doc.moveDown(1);

    // Table headers
    const tableTop = doc.y;
    const col1 = 50;
    const col2 = 150;
    const col3 = 250;
    const col4 = 350;
    const col5 = 450;

    doc.fontSize(10).font('Helvetica-Bold');
    doc.text('Employee', col1, tableTop);
    doc.text('Date', col2, tableTop);
    doc.text('Check In', col3, tableTop);
    doc.text('Check Out', col4, tableTop);
    doc.text('Location', col5, tableTop);

    // Horizontal line
    doc.moveTo(50, tableTop + 15).lineTo(550, tableTop + 15).stroke();

    // Table rows
    let yPosition = tableTop + 25;
    const pageHeight = doc.page.height;
    const bottomMargin = 50;

    doc.fontSize(9).font('Helvetica');

    records.forEach((record) => {
      // Check if we need a new page
      if (yPosition > pageHeight - bottomMargin) {
        doc.addPage();
        yPosition = 50;

        // Repeat headers on new page
        doc.fontSize(10).font('Helvetica-Bold');
        doc.text('Employee', col1, yPosition);
        doc.text('Date', col2, yPosition);
        doc.text('Check In', col3, yPosition);
        doc.text('Check Out', col4, yPosition);
        doc.text('Location', col5, yPosition);
        doc.moveTo(50, yPosition + 15).lineTo(550, yPosition + 15).stroke();
        yPosition += 25;
        doc.font('Helvetica');
      }

      const date = new Date(record.timestamp).toLocaleDateString();
      const time = new Date(record.timestamp).toLocaleTimeString();
      const status = record.isCheckIn ? time : '-';
      const checkOut = !record.isCheckIn ? time : '-';

      doc.text(record.userId || 'N/A', col1, yPosition);
      doc.text(date, col2, yPosition);
      doc.text(status, col3, yPosition);
      doc.text(checkOut, col4, yPosition);
      doc.text(record.geofenceName || 'N/A', col5, yPosition);

      yPosition += 20;
    });

    // Footer
    doc.fontSize(8).font('Helvetica');
    doc.text('FieldCheck - Attendance Verification System', 50, pageHeight - 30, { align: 'center' });

    doc.end();
    return doc;
  }

  /**
   * Generate PDF report for task records
   * @param {Array} tasks - Task records
   * @param {Object} options - Export options
   * @returns {Stream} PDF stream
   */
  static generateTaskPDF(tasks, options = {}) {
    const doc = new PDFDocument({
      margin: 50,
      size: 'A4',
    });

    // Title
    doc.fontSize(20).font('Helvetica-Bold').text('Task Report', { align: 'center' });
    doc.moveDown(0.5);

    // Report metadata
    doc.fontSize(10).font('Helvetica');
    doc.text(`Generated: ${new Date().toLocaleString()}`, { align: 'center' });
    if (options.dateRange) {
      doc.text(`Period: ${options.dateRange}`, { align: 'center' });
    }
    doc.moveDown(1);

    // Table headers
    const tableTop = doc.y;
    const col1 = 50;
    const col2 = 180;
    const col3 = 320;
    const col4 = 450;

    doc.fontSize(10).font('Helvetica-Bold');
    doc.text('Task Title', col1, tableTop);
    doc.text('Assigned To', col2, tableTop);
    doc.text('Status', col3, tableTop);
    doc.text('Due Date', col4, tableTop);

    // Horizontal line
    doc.moveTo(50, tableTop + 15).lineTo(550, tableTop + 15).stroke();

    // Table rows
    let yPosition = tableTop + 25;
    const pageHeight = doc.page.height;
    const bottomMargin = 50;

    doc.fontSize(9).font('Helvetica');

    tasks.forEach((task) => {
      // Check if we need a new page
      if (yPosition > pageHeight - bottomMargin) {
        doc.addPage();
        yPosition = 50;

        // Repeat headers on new page
        doc.fontSize(10).font('Helvetica-Bold');
        doc.text('Task Title', col1, yPosition);
        doc.text('Assigned To', col2, yPosition);
        doc.text('Status', col3, yPosition);
        doc.text('Due Date', col4, yPosition);
        doc.moveTo(50, yPosition + 15).lineTo(550, yPosition + 15).stroke();
        yPosition += 25;
        doc.font('Helvetica');
      }

      const dueDate = new Date(task.dueDate).toLocaleDateString();
      const assignedTo = task.assignedTo?.name || 'Unassigned';
      const statusColor = task.status === 'completed' ? 'green' : task.status === 'in_progress' ? 'blue' : 'black';

      doc.text(task.title || 'N/A', col1, yPosition);
      doc.text(assignedTo, col2, yPosition);
      doc.fillColor(statusColor).text(task.status || 'N/A', col3, yPosition);
      doc.fillColor('black').text(dueDate, col4, yPosition);

      yPosition += 20;
    });

    // Footer
    doc.fontSize(8).font('Helvetica');
    doc.text('FieldCheck - Task Management System', 50, pageHeight - 30, { align: 'center' });

    doc.end();
    return doc;
  }

  /**
   * Generate Excel report for attendance records
   * @param {Array} records - Attendance records
   * @param {Object} options - Export options
   * @returns {Promise<Buffer>} Excel file buffer
   */
  static async generateAttendanceExcel(records, options = {}) {
    const workbook = new ExcelJS.Workbook();
    const worksheet = workbook.addWorksheet('Attendance', {
      pageSetup: { paperSize: 9, orientation: 'landscape' },
    });

    // Add title
    worksheet.mergeCells('A1:E1');
    const titleCell = worksheet.getCell('A1');
    titleCell.value = 'Attendance Report';
    titleCell.font = { bold: true, size: 14 };
    titleCell.alignment = { horizontal: 'center', vertical: 'center' };

    // Add metadata
    worksheet.mergeCells('A2:E2');
    const metaCell = worksheet.getCell('A2');
    metaCell.value = `Generated: ${new Date().toLocaleString()}`;
    metaCell.font = { size: 10 };
    metaCell.alignment = { horizontal: 'center' };

    // Add headers
    const headerRow = worksheet.addRow(['Employee', 'Date', 'Check In Time', 'Check Out Time', 'Location']);
    headerRow.font = { bold: true, color: { argb: 'FFFFFFFF' } };
    headerRow.fill = { type: 'pattern', pattern: 'solid', fgColor: { argb: 'FF2688d4' } };
    headerRow.alignment = { horizontal: 'center', vertical: 'center' };

    // Group records by employee and date
    const groupedRecords = {};
    records.forEach((record) => {
      const key = `${record.userId}_${new Date(record.timestamp).toLocaleDateString()}`;
      if (!groupedRecords[key]) {
        groupedRecords[key] = {
          userId: record.userId,
          date: new Date(record.timestamp).toLocaleDateString(),
          location: record.geofenceName || 'N/A',
          checkIn: null,
          checkOut: null,
        };
      }
      if (record.isCheckIn) {
        groupedRecords[key].checkIn = new Date(record.timestamp).toLocaleTimeString();
      } else {
        groupedRecords[key].checkOut = new Date(record.timestamp).toLocaleTimeString();
      }
    });

    // Add data rows
    Object.values(groupedRecords).forEach((record) => {
      const row = worksheet.addRow([
        record.userId || 'N/A',
        record.date,
        record.checkIn || '-',
        record.checkOut || '-',
        record.location,
      ]);
      row.alignment = { horizontal: 'center', vertical: 'center' };
    });

    // Set column widths
    worksheet.columns = [
      { width: 20 },
      { width: 15 },
      { width: 15 },
      { width: 15 },
      { width: 20 },
    ];

    // Generate buffer
    const buffer = await workbook.xlsx.writeBuffer();
    return buffer;
  }

  /**
   * Generate Excel report for task records
   * @param {Array} tasks - Task records
   * @param {Object} options - Export options
   * @returns {Promise<Buffer>} Excel file buffer
   */
  static async generateTaskExcel(tasks, options = {}) {
    const workbook = new ExcelJS.Workbook();
    const worksheet = workbook.addWorksheet('Tasks', {
      pageSetup: { paperSize: 9, orientation: 'landscape' },
    });

    // Add title
    worksheet.mergeCells('A1:D1');
    const titleCell = worksheet.getCell('A1');
    titleCell.value = 'Task Report';
    titleCell.font = { bold: true, size: 14 };
    titleCell.alignment = { horizontal: 'center', vertical: 'center' };

    // Add metadata
    worksheet.mergeCells('A2:D2');
    const metaCell = worksheet.getCell('A2');
    metaCell.value = `Generated: ${new Date().toLocaleString()}`;
    metaCell.font = { size: 10 };
    metaCell.alignment = { horizontal: 'center' };

    // Add headers
    const headerRow = worksheet.addRow(['Task Title', 'Assigned To', 'Status', 'Due Date']);
    headerRow.font = { bold: true, color: { argb: 'FFFFFFFF' } };
    headerRow.fill = { type: 'pattern', pattern: 'solid', fgColor: { argb: 'FF2688d4' } };
    headerRow.alignment = { horizontal: 'center', vertical: 'center' };

    // Add data rows
    tasks.forEach((task) => {
      const row = worksheet.addRow([
        task.title || 'N/A',
        task.assignedTo?.name || 'Unassigned',
        task.status || 'N/A',
        new Date(task.dueDate).toLocaleDateString(),
      ]);
      row.alignment = { horizontal: 'center', vertical: 'center' };

      // Color code status
      const statusCell = row.getCell(3);
      if (task.status === 'completed') {
        statusCell.fill = { type: 'pattern', pattern: 'solid', fgColor: { argb: 'FF90EE90' } };
      } else if (task.status === 'in_progress') {
        statusCell.fill = { type: 'pattern', pattern: 'solid', fgColor: { argb: 'FFFFFF99' } };
      }
    });

    // Set column widths
    worksheet.columns = [
      { width: 30 },
      { width: 20 },
      { width: 15 },
      { width: 15 },
    ];

    // Generate buffer
    const buffer = await workbook.xlsx.writeBuffer();
    return buffer;
  }

  /**
   * Generate combined Excel report with multiple sheets
   * @param {Object} data - Data object with attendance and tasks
   * @returns {Promise<Buffer>} Excel file buffer
   */
  static async generateCombinedExcel(data) {
    const workbook = new ExcelJS.Workbook();

    // Attendance sheet
    if (data.attendance && data.attendance.length > 0) {
      const attendanceSheet = workbook.addWorksheet('Attendance');
      const headerRow = attendanceSheet.addRow(['Employee', 'Date', 'Check In Time', 'Check Out Time', 'Location']);
      headerRow.font = { bold: true, color: { argb: 'FFFFFFFF' } };
      headerRow.fill = { type: 'pattern', pattern: 'solid', fgColor: { argb: 'FF2688d4' } };

      const groupedRecords = {};
      data.attendance.forEach((record) => {
        const key = `${record.userId}_${new Date(record.timestamp).toLocaleDateString()}`;
        if (!groupedRecords[key]) {
          groupedRecords[key] = {
            userId: record.userId,
            date: new Date(record.timestamp).toLocaleDateString(),
            location: record.geofenceName || 'N/A',
            checkIn: null,
            checkOut: null,
          };
        }
        if (record.isCheckIn) {
          groupedRecords[key].checkIn = new Date(record.timestamp).toLocaleTimeString();
        } else {
          groupedRecords[key].checkOut = new Date(record.timestamp).toLocaleTimeString();
        }
      });

      Object.values(groupedRecords).forEach((record) => {
        attendanceSheet.addRow([
          record.userId || 'N/A',
          record.date,
          record.checkIn || '-',
          record.checkOut || '-',
          record.location,
        ]);
      });

      attendanceSheet.columns = [
        { width: 20 },
        { width: 15 },
        { width: 15 },
        { width: 15 },
        { width: 20 },
      ];
    }

    // Tasks sheet
    if (data.tasks && data.tasks.length > 0) {
      const tasksSheet = workbook.addWorksheet('Tasks');
      const headerRow = tasksSheet.addRow(['Task Title', 'Assigned To', 'Status', 'Due Date']);
      headerRow.font = { bold: true, color: { argb: 'FFFFFFFF' } };
      headerRow.fill = { type: 'pattern', pattern: 'solid', fgColor: { argb: 'FF2688d4' } };

      data.tasks.forEach((task) => {
        tasksSheet.addRow([
          task.title || 'N/A',
          task.assignedTo?.name || 'Unassigned',
          task.status || 'N/A',
          new Date(task.dueDate).toLocaleDateString(),
        ]);
      });

      tasksSheet.columns = [
        { width: 30 },
        { width: 20 },
        { width: 15 },
        { width: 15 },
      ];
    }

    const buffer = await workbook.xlsx.writeBuffer();
    return buffer;
  }
}

module.exports = ReportExportService;
