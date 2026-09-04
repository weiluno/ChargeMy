import 'dart:convert';

import 'package:csv/csv.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/app_state.dart';
import '../../core/widgets.dart';

class ImportScreen extends ConsumerStatefulWidget {
  const ImportScreen({super.key});

  @override
  ConsumerState<ImportScreen> createState() => _ImportScreenState();
}

class _ImportScreenState extends ConsumerState<ImportScreen> {
  String? _fileName;
  String? _format;
  List<Map<String, dynamic>> _rows = const [];
  List<String> _parseErrors = const [];
  bool _importing = false;
  String? _result;

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('CSV / JSON import')),
    body: ListView(
      padding: const EdgeInsets.all(20),
      children: [
        Text(
          'Import prototype stations',
          style: Theme.of(context).textTheme.headlineSmall,
        ),
        const SizedBox(height: 8),
        const Text(
          'Administrators can import up to 500 rows. The server validates Malaysian coordinates, name, power and price before every row is saved.',
        ),
        const SizedBox(height: 18),
        OutlinedButton.icon(
          onPressed: _importing ? null : _pickFile,
          icon: const Icon(Icons.upload_file_outlined),
          label: const Text('Choose CSV or JSON file'),
        ),
        if (_fileName != null) ...[
          const SizedBox(height: 16),
          Card(
            child: ListTile(
              leading: const Icon(Icons.description_outlined),
              title: Text(_fileName!),
              subtitle: Text(
                '${_rows.length} parsed row(s) • ${_format!.toUpperCase()}',
              ),
            ),
          ),
        ],
        const SizedBox(height: 18),
        const Text('Required columns'),
        const SizedBox(height: 6),
        const SelectableText(
          'name, latitude, longitude, power_kw, price_per_kwh\nOptional: station_id, pile_id, address, brand, indoor_outdoor, local_authority, pile_label, connector_type, operational_state',
        ),
        if (_parseErrors.isNotEmpty) ...[
          const SizedBox(height: 18),
          Text('File issues', style: Theme.of(context).textTheme.titleMedium),
          for (final error in _parseErrors) Text('• $error'),
        ],
        if (_result != null) ...[
          const SizedBox(height: 18),
          Card(
            color: Theme.of(context).colorScheme.secondaryContainer,
            child: Padding(
              padding: const EdgeInsets.all(14),
              child: Text(_result!),
            ),
          ),
        ],
        const SizedBox(height: 24),
        FilledButton.icon(
          onPressed: _rows.isEmpty || _importing ? null : _upload,
          icon: const Icon(Icons.cloud_upload_outlined),
          label: Text(
            _importing
                ? 'Importing…'
                : 'Validate and import ${_rows.length} row(s)',
          ),
        ),
      ],
    ),
  );

  Future<void> _pickFile() async {
    final selected = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: const ['csv', 'json'],
      withData: true,
    );
    if (selected == null) return;
    final file = selected.files.single;
    final bytes = file.bytes;
    if (bytes == null) {
      setState(
        () => _parseErrors = const ['Could not read the selected file.'],
      );
      return;
    }
    try {
      final format = file.extension?.toLowerCase();
      if (format != 'csv' && format != 'json') {
        throw const FormatException('Choose a .csv or .json file.');
      }
      final rows =
          format == 'csv'
              ? _parseCsv(utf8.decode(bytes))
              : _parseJson(utf8.decode(bytes));
      if (rows.length > 500) {
        throw const FormatException('Use a maximum of 500 rows per import.');
      }
      setState(() {
        _fileName = file.name;
        _format = format;
        _rows = rows;
        _parseErrors = const [];
        _result = null;
      });
    } catch (error) {
      setState(() {
        _rows = const [];
        _parseErrors = [
          friendlyErrorMessage(
            error,
            fallback: 'The selected file could not be read.',
          ),
        ];
        _result = null;
      });
    }
  }

  List<Map<String, dynamic>> _parseCsv(String text) {
    final cells = const CsvToListConverter(
      shouldParseNumbers: false,
    ).convert(text);
    if (cells.length < 2) {
      throw const FormatException(
        'CSV needs a header row and at least one data row.',
      );
    }
    final headers =
        cells.first.map((value) => '$value'.trim().toLowerCase()).toList();
    if (!headers.contains('name') ||
        !headers.contains('latitude') ||
        !headers.contains('longitude')) {
      throw const FormatException(
        'CSV must include name, latitude and longitude headers.',
      );
    }
    return cells
        .skip(1)
        .where((row) => row.any((value) => '$value'.trim().isNotEmpty))
        .map((row) {
          return {
            for (var index = 0; index < headers.length; index++)
              headers[index]: index < row.length ? '${row[index]}'.trim() : '',
          };
        })
        .toList();
  }

  List<Map<String, dynamic>> _parseJson(String text) {
    final decoded = jsonDecode(text);
    final values =
        decoded is List
            ? decoded
            : decoded is Map && decoded['rows'] is List
            ? decoded['rows'] as List
            : null;
    if (values == null || values.isEmpty) {
      throw const FormatException(
        'JSON must be an array of station rows, or contain a rows array.',
      );
    }
    return values
        .map((value) {
          if (value is! Map) {
            throw const FormatException('Every JSON row must be an object.');
          }
          return value.map((key, item) => MapEntry('$key'.toLowerCase(), item));
        })
        .cast<Map<String, dynamic>>()
        .toList();
  }

  Future<void> _upload() async {
    setState(() => _importing = true);
    try {
      final summary = await ref
          .read(stationRepositoryProvider)
          .bulkImport(fileName: _fileName!, format: _format!, rows: _rows);
      if (!mounted) return;
      setState(() {
        _result =
            'Imported ${summary.importedRows} of ${summary.totalRows} row(s).'
            '${summary.errors.isEmpty ? '' : '\n\nErrors:\n${summary.errors.take(12).join('\n')}'}';
      });
    } catch (error) {
      if (mounted) {
        setState(
          () =>
              _result = friendlyErrorMessage(
                error,
                fallback: 'Import failed. Check the file and try again.',
              ),
        );
      }
    } finally {
      if (mounted) setState(() => _importing = false);
    }
  }
}
