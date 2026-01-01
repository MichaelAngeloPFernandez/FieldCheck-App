export 'export_service_stub.dart' show ExportResult;

import 'export_service_stub.dart';

import 'export_service_web.dart'
    if (dart.library.io) 'export_service_io.dart'
    as impl;

ExportService createExportService() => impl.ExportServiceImpl();
