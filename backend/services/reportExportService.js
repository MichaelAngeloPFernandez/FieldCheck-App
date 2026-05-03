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

    // Helper function to format time as HH:MM AM/PM
    const formatTime = (date) => {
      if (!date) return '-';
      const d = new Date(date);
      const hours = d.getHours();
      const minutes = String(d.getMinutes()).padStart(2, '0');
      const ampm = hours >= 12 ? 'PM' : 'AM';
      const displayHours = hours % 12 || 12;
      return `${String(displayHours).padStart(2, '0')}:${minutes} ${ampm}`;
    };

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

      const checkInDate = new Date(record.checkIn);
      const date = checkInDate.toLocaleDateString();
      const checkInTime = formatTime(record.checkIn);
      const checkOutTime = formatTime(record.checkOut);
      const employeeName = record.employee?.name || record.userId || 'N/A';
      const locationName = record.geofence?.name || 'N/A';

      doc.text(employeeName, col1, yPosition);
      doc.text(date, col2, yPosition);
      doc.text(checkInTime, col3, yPosition);
      doc.text(checkOutTime, col4, yPosition);
      doc.text(locationName, col5, yPosition);

      yPosition += 20;
    });

    // Add Tasks Section if tasks are provided
    if (options.tasks && options.tasks.length > 0) {
      yPosition += 20;
      
      // Add page break if needed
      if (yPosition > pageHeight - 150) {
        doc.addPage();
        yPosition = 50;
      }

      // Tasks title
      doc.fontSize(14).font('Helvetica-Bold').text('Tasks Completed', 50, yPosition);
      yPosition += 20;

      // Task headers
      const taskCol1 = 50;
      const taskCol2 = 200;
      const taskCol3 = 350;
      const taskCol4 = 450;

      doc.fontSize(10).font('Helvetica-Bold');
      doc.text('Task Title', taskCol1, yPosition);
      doc.text('Status', taskCol2, yPosition);
      doc.text('Due Date', taskCol3, yPosition);
      doc.text('Assigned By', taskCol4, yPosition);

      // Horizontal line
      doc.moveTo(50, yPosition + 15).lineTo(550, yPosition + 15).stroke();
      yPosition += 25;

      doc.fontSize(9).font('Helvetica');

      // Add task rows
      options.tasks.forEach((task) => {
        // Check if we need a new page
        if (yPosition > pageHeight - bottomMargin) {
          doc.addPage();
          yPosition = 50;

          // Repeat headers on new page
          doc.fontSize(10).font('Helvetica-Bold');
          doc.text('Task Title', taskCol1, yPosition);
          doc.text('Status', taskCol2, yPosition);
          doc.text('Due Date', taskCol3, yPosition);
          doc.text('Assigned By', taskCol4, yPosition);
          doc.moveTo(50, yPosition + 15).lineTo(550, yPosition + 15).stroke();
          yPosition += 25;
          doc.font('Helvetica');
        }

        const dueDate = new Date(task.dueDate).toLocaleDateString();
        const assignedBy = task.assignedBy?.name || 'Unknown';
        const taskStatus = task.status || 'pending';

        doc.text(task.title || 'N/A', taskCol1, yPosition);
        doc.text(taskStatus, taskCol2, yPosition);
        doc.text(dueDate, taskCol3, yPosition);
        doc.text(assignedBy, taskCol4, yPosition);

        yPosition += 20;
      });
    }

    // Footer
    doc.fontSize(8).font('Helvetica');
    doc.text('FieldCheck - Attendance Verification System', 50, pageHeight - 30, { align: 'center' });

    doc.end();
    return doc;
  }

  static generateTaskReportPDF(rows, options = {}) {
    const doc = new PDFDocument({
      margin: 50,
      size: 'A4',
    });

    doc.fontSize(20).font('Helvetica-Bold').text('Task Reports', { align: 'center' });
    doc.moveDown(0.5);

    doc.fontSize(10).font('Helvetica');
    doc.text(`Generated: ${new Date().toLocaleString()}`, { align: 'center' });
    if (options.dateRange) {
      doc.text(`Period: ${options.dateRange}`, { align: 'center' });
    }
    doc.moveDown(1);

    const tableTop = doc.y;
    const col1 = 50;
    const col2 = 150;
    const col3 = 300;
    const col4 = 380;
    const col5 = 450;
    const col6 = 510;

    doc.fontSize(10).font('Helvetica-Bold');
    doc.text('Employee', col1, tableTop);
    doc.text('Task', col2, tableTop);
    doc.text('Submitted', col3, tableTop);
    doc.text('Status', col4, tableTop);
    doc.text('Grade', col5, tableTop);
    doc.text('Overdue', col6, tableTop);

    doc.moveTo(50, tableTop + 15).lineTo(550, tableTop + 15).stroke();

    let yPosition = tableTop + 25;
    const pageHeight = doc.page.height;
    const bottomMargin = 50;

    doc.fontSize(9).font('Helvetica');

    rows.forEach((r) => {
      if (yPosition > pageHeight - bottomMargin) {
        doc.addPage();
        yPosition = 50;

        doc.fontSize(10).font('Helvetica-Bold');
        doc.text('Employee', col1, yPosition);
        doc.text('Task', col2, yPosition);
        doc.text('Submitted', col3, yPosition);
        doc.text('Status', col4, yPosition);
        doc.text('Grade', col5, yPosition);
        doc.text('Overdue', col6, yPosition);
        doc.moveTo(50, yPosition + 15).lineTo(550, yPosition + 15).stroke();
        yPosition += 25;
        doc.font('Helvetica');
      }

      const employee = r.employeeName || r.employeeEmail || 'N/A';
      const taskTitle = r.taskTitle || 'N/A';
      const submitted = r.submittedAt ? new Date(r.submittedAt).toLocaleString() : '-';
      const status = r.reportStatus || '-';
      const grade = r.grade || '-';
      const overdue = r.taskIsOverdue ? 'YES' : 'NO';

      doc.text(employee, col1, yPosition, { width: col2 - col1 - 5 });
      doc.text(taskTitle, col2, yPosition, { width: col3 - col2 - 5 });
      doc.text(submitted, col3, yPosition, { width: col4 - col3 - 5 });
      doc.text(status, col4, yPosition, { width: col5 - col4 - 5 });
      doc.text(grade, col5, yPosition, { width: col6 - col5 - 5 });
      doc.text(overdue, col6, yPosition, { width: 40 });

      yPosition += 18;

      const attachmentsRaw = (r.attachments || '').toString().trim();
      if (attachmentsRaw) {
        const lines = attachmentsRaw.split(/\r?\n/).filter(Boolean);
        if (lines.length) {
          const toShow = lines.slice(0, 3);
          doc.fontSize(8).fillColor('gray');
          doc.text(`Attachments: ${toShow.join(' | ')}${lines.length > 3 ? ' | ...' : ''}`, 50, yPosition, {
            width: 500,
          });
          doc.fillColor('black').fontSize(9);
          yPosition += 14;
        }
      }
    });

    doc.fontSize(8).font('Helvetica');
    doc.text('FieldCheck - Task Reports', 50, pageHeight - 30, { align: 'center' });

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
    const headerRow = worksheet.addRow(['Employee', 'Date', 'Time', 'Status', 'Location']);
    headerRow.font = { bold: true, color: { argb: 'FFFFFFFF' } };
    headerRow.fill = { type: 'pattern', pattern: 'solid', fgColor: { argb: 'FF2688d4' } };
    headerRow.alignment = { horizontal: 'center', vertical: 'center' };

    // Add data rows - show each check-in/out as separate row
    records.forEach((record) => {
      const date = new Date(record.checkIn || record.timestamp).toLocaleDateString();
      const time = new Date(record.checkIn || record.timestamp).toLocaleTimeString();
      const employeeName = record.employee?.name || record.userId || 'N/A';
      const locationName = record.geofence?.name || 'N/A';
      const status = record.status === 'in' ? 'Checked In' : 'Checked Out';
      
      const row = worksheet.addRow([
        employeeName,
        date,
        time,
        status,
        locationName,
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

    // Add Tasks worksheet if tasks are provided
    if (options.tasks && options.tasks.length > 0) {
      const tasksWorksheet = workbook.addWorksheet('Tasks', {
        pageSetup: { paperSize: 9, orientation: 'landscape' },
      });

      // Add title
      tasksWorksheet.mergeCells('A1:D1');
      const tasksTitleCell = tasksWorksheet.getCell('A1');
      tasksTitleCell.value = 'Tasks Report';
      tasksTitleCell.font = { bold: true, size: 14 };
      tasksTitleCell.alignment = { horizontal: 'center', vertical: 'center' };

      // Add metadata
      tasksWorksheet.mergeCells('A2:D2');
      const tasksMetaCell = tasksWorksheet.getCell('A2');
      tasksMetaCell.value = `Generated: ${new Date().toLocaleString()}`;
      tasksMetaCell.font = { size: 10 };
      tasksMetaCell.alignment = { horizontal: 'center' };

      // Add headers
      const tasksHeaderRow = tasksWorksheet.addRow(['Task Title', 'Status', 'Due Date', 'Assigned By']);
      tasksHeaderRow.font = { bold: true, color: { argb: 'FFFFFFFF' } };
      tasksHeaderRow.fill = { type: 'pattern', pattern: 'solid', fgColor: { argb: 'FF2688d4' } };
      tasksHeaderRow.alignment = { horizontal: 'center', vertical: 'center' };

      // Add task rows
      options.tasks.forEach((task) => {
        const dueDate = new Date(task.dueDate).toLocaleDateString();
        const assignedBy = task.assignedBy?.name || 'Unknown';
        const taskStatus = task.status || 'pending';

        const row = tasksWorksheet.addRow([
          task.title || 'N/A',
          taskStatus,
          dueDate,
          assignedBy,
        ]);
        row.alignment = { horizontal: 'center', vertical: 'center' };
      });

      // Set column widths
      tasksWorksheet.columns = [
        { width: 30 },
        { width: 15 },
        { width: 15 },
        { width: 20 },
      ];
    }

    // Generate buffer
    const buffer = await workbook.xlsx.writeBuffer();
    return buffer;
  }

  static async generateTaskReportExcel(rows, options = {}) {
    const workbook = new ExcelJS.Workbook();
    const worksheet = workbook.addWorksheet('Task Reports', {
      pageSetup: { paperSize: 9, orientation: 'landscape' },
    });

    const maxAttachments = rows.reduce((max, r) => {
      const list = Array.isArray(r.attachments)
        ? r.attachments
        : String(r.attachments || '')
            .split(/\r?\n/)
            .filter(Boolean);
      return Math.max(max, list.length);
    }, 0);

    const baseHeaders = [
      'Report ID',
      'Employee',
      'Employee Email',
      'Employee Code',
      'Task',
      'Task Difficulty',
      'Submitted At',
      'Report Status',
      'Grade',
      'Task Due Date',
      'Overdue',
      'Attachment Count',
    ];
    const attachmentHeaders = Array.from({ length: maxAttachments }, (_, i) => `Attachment ${i + 1}`);
    const headers = [...baseHeaders, ...attachmentHeaders];

    const lastColLetter = worksheet.getColumn(headers.length).letter;

    worksheet.mergeCells(`A1:${lastColLetter}1`);
    const titleCell = worksheet.getCell('A1');
    titleCell.value = 'Task Reports';
    titleCell.font = { bold: true, size: 14 };
    titleCell.alignment = { horizontal: 'center', vertical: 'center' };

    worksheet.mergeCells(`A2:${lastColLetter}2`);
    const metaCell = worksheet.getCell('A2');
    metaCell.value = `Generated: ${new Date().toLocaleString()}`;
    metaCell.font = { size: 10 };
    metaCell.alignment = { horizontal: 'center' };

    const headerRow = worksheet.addRow(headers);
    headerRow.font = { bold: true, color: { argb: 'FFFFFFFF' } };
    headerRow.fill = { type: 'pattern', pattern: 'solid', fgColor: { argb: 'FF2688d4' } };
    headerRow.alignment = { horizontal: 'center', vertical: 'center', wrapText: true };

    rows.forEach((r) => {
      const attachments = Array.isArray(r.attachments)
        ? r.attachments
        : String(r.attachments || '')
            .split(/\r?\n/)
            .filter(Boolean);

      const submittedAt = r.submittedAt ? new Date(r.submittedAt) : null;
      const dueDate = r.taskDueDate ? new Date(r.taskDueDate) : null;

      const row = worksheet.addRow([
        r.reportId || '',
        r.employeeName || '',
        r.employeeEmail || '',
        r.employeeCode || '',
        r.taskTitle || '',
        r.taskDifficulty || '',
        submittedAt || '',
        r.reportStatus || '',
        r.grade || '',
        dueDate || '',
        r.taskIsOverdue ? 'YES' : 'NO',
        typeof r.attachmentCount === 'number' ? r.attachmentCount : attachments.length,
        ...Array.from({ length: maxAttachments }, (_, i) => attachments[i] || ''),
      ]);

      row.alignment = { vertical: 'center', wrapText: true };

      const submittedCell = row.getCell(baseHeaders.indexOf('Submitted At') + 1);
      submittedCell.numFmt = 'yyyy-mm-dd hh:mm';
      const dueCell = row.getCell(baseHeaders.indexOf('Task Due Date') + 1);
      dueCell.numFmt = 'yyyy-mm-dd';

      const overdueCell = row.getCell(baseHeaders.indexOf('Overdue') + 1);
      if (r.taskIsOverdue) {
        overdueCell.fill = { type: 'pattern', pattern: 'solid', fgColor: { argb: 'FFFFC7CE' } };
      }

      const firstAttachmentCol = baseHeaders.length + 1;
      attachments.slice(0, maxAttachments).forEach((url, idx) => {
        const cell = row.getCell(firstAttachmentCol + idx);
        const value = String(url || '').trim();
        if (!value) return;

        const displayText = value.split('/').pop() || value;
        cell.value = { text: displayText, hyperlink: value };
        cell.font = { color: { argb: 'FF0563C1' }, underline: true };
      });
    });

    worksheet.columns = headers.map((h, idx) => {
      if (h.startsWith('Attachment ')) return { width: 28 };
      if (idx === 0) return { width: 26 };
      if (h === 'Employee') return { width: 20 };
      if (h === 'Employee Email') return { width: 26 };
      if (h === 'Task') return { width: 30 };
      if (h === 'Submitted At') return { width: 20 };
      if (h === 'Task Due Date') return { width: 15 };
      return { width: 15 };
    });

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

  /**
   * Generate CSV report for attendance records
   * @param {Array} records - Attendance records
   * @param {Array} tasks - Tasks array
   * @returns {String} CSV string
   */
  static generateAttendanceCSV(records, tasks = []) {
    let csv = 'Employee,Date,Check In Time,Check Out Time,Location\n';

    // Helper function to format time as HH:MM AM/PM
    // Times are already stored in PH timezone (UTC+8) in MongoDB
    const _manilaTimeFormatter = new Intl.DateTimeFormat('en-US', {
      timeZone: 'Asia/Manila',
      hour: '2-digit',
      minute: '2-digit',
      hour12: true,
    });

    const _manilaDateFormatter = new Intl.DateTimeFormat('en-CA', {
      timeZone: 'Asia/Manila',
      year: 'numeric',
      month: '2-digit',
      day: '2-digit',
    });

    const formatTime = (date) => {
      if (!date) return '-';
      return _manilaTimeFormatter.format(new Date(date));
    };

    // Each record has both checkIn and checkOut times
    records.forEach((record) => {
      const date = _manilaDateFormatter.format(new Date(record.checkIn)); // YYYY-MM-DD format
      
      const employeeName = record.employee?.name || 'N/A';
      const locationName = record.geofence?.name || 'N/A';
      
      const checkInTime = formatTime(record.checkIn);
      const checkOutTime = formatTime(record.checkOut);
      
      // Escape quotes in values
      const escapedEmployee = employeeName.replace(/"/g, '""');
      const escapedLocation = locationName.replace(/"/g, '""');
      
      csv += `"${escapedEmployee}","${date}","${checkInTime}","${checkOutTime}","${escapedLocation}"\n`;
    });

    // Add tasks section if present
    if (tasks && tasks.length > 0) {
      csv += '\n\nTasks Completed\n';
      csv += 'Task Title,Status,Due Date,Assigned By\n';

      tasks.forEach((task) => {
        const dueDate = new Date(task.dueDate).toLocaleDateString();
        const assignedBy = task.assignedBy?.name || 'Unknown';
        const taskStatus = task.status || 'pending';

        const escapedTitle = (task.title || 'N/A').replace(/"/g, '""');
        const escapedAssignedBy = assignedBy.replace(/"/g, '""');

        csv += `"${escapedTitle}","${taskStatus}","${dueDate}","${escapedAssignedBy}"\n`;
      });
    }

    return csv;
  }
}

module.exports = ReportExportService;
