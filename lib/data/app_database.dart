import 'dart:io';

import 'package:drift/drift.dart';
import 'package:drift_flutter/drift_flutter.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

part 'app_database.g.dart';

class Clients extends Table {
  IntColumn get id => integer().autoIncrement()();
  TextColumn get name => text()();
  TextColumn get phone => text().nullable()();
  TextColumn get email => text().nullable()();
  TextColumn get notes => text().nullable()();
  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();
  DateTimeColumn get updatedAt => dateTime().nullable()();
}

class Vessels extends Table {
  IntColumn get id => integer().autoIncrement()();
  IntColumn get clientId => integer().references(Clients, #id)();
  TextColumn get name => text()();
  TextColumn get make => text().nullable()();
  TextColumn get model => text().nullable()();
  IntColumn get year => integer().nullable()();
  TextColumn get hin => text().nullable()();
  TextColumn get notes => text().nullable()();
  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();
  DateTimeColumn get updatedAt => dateTime().nullable()();
}

class Equipment extends Table {
  IntColumn get id => integer().autoIncrement()();
  IntColumn get vesselId => integer().references(Vessels, #id)();
  TextColumn get name => text()();
  TextColumn get manufacturer => text().nullable()();
  TextColumn get model => text().nullable()();
  TextColumn get serialNumber => text()();
  DateTimeColumn get installedAt => dateTime().nullable()();
  TextColumn get notes => text().nullable()();
}

class WorkOrders extends Table {
  IntColumn get id => integer().autoIncrement()();
  IntColumn get clientId => integer().references(Clients, #id)();
  IntColumn get vesselId => integer().references(Vessels, #id)();
  TextColumn get title => text()();
  TextColumn get status =>
      text().withDefault(const Constant('open'))(); // open, closed, invoiced
  DateTimeColumn get openedAt => dateTime().withDefault(currentDateAndTime)();
  DateTimeColumn get closedAt => dateTime().nullable()();
  TextColumn get notes => text().nullable()();
}

class Categories extends Table {
  IntColumn get id => integer().autoIncrement()();
  TextColumn get name => text()();
  TextColumn get colorHex => text().nullable()();
}

class LineItems extends Table {
  IntColumn get id => integer().autoIncrement()();
  IntColumn get workOrderId => integer().references(WorkOrders, #id)();
  IntColumn get equipmentId => integer().nullable().references(Equipment, #id)();
  IntColumn get categoryId => integer().nullable().references(Categories, #id)();
  TextColumn get type => text()(); // labor, part
  TextColumn get description => text()();
  RealColumn get quantity =>
      real().withDefault(const Constant(1.0))(); // parts or hours override
  RealColumn get unitPrice =>
      real().withDefault(const Constant(0.0))(); // hourly rate or part price
  IntColumn get flaggedSeconds =>
      integer().withDefault(const Constant(0))(); // actual time
  IntColumn get billedSeconds =>
      integer().withDefault(const Constant(0))(); // invoice time
  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();
}

class Media extends Table {
  IntColumn get id => integer().autoIncrement()();
  IntColumn get workOrderId => integer().references(WorkOrders, #id)();
  TextColumn get filePath => text()();
  TextColumn get caption => text().nullable()();
  DateTimeColumn get takenAt => dateTime().withDefault(currentDateAndTime)();
}

@DriftDatabase(
  tables: [Clients, Vessels, Equipment, WorkOrders, LineItems, Media, Categories],
)
class AppDatabase extends _$AppDatabase {
  AppDatabase() : super(_openConnection());

  @override
  int get schemaVersion => 1;

  Future<int> addFromHistory({
    required int sourceLineItemId,
    required int targetWorkOrderId,
  }) async {
    final source = await (select(lineItems)
          ..where((tbl) => tbl.id.equals(sourceLineItemId)))
        .getSingle();

    final entry = LineItemsCompanion.insert(
      workOrderId: targetWorkOrderId,
      equipmentId: Value(source.equipmentId),
      categoryId: Value(source.categoryId),
      type: source.type,
      description: source.description,
      quantity: source.quantity,
      unitPrice: source.unitPrice,
      flaggedSeconds: const Value(0),
      billedSeconds: const Value(0),
    );

    return into(lineItems).insert(entry);
  }

  Future<List<CategoryRate>> categoryProfitabilityReport({
    required DateTime from,
    required DateTime to,
  }) async {
    final billedHours =
        lineItems.billedSeconds.cast<double>() / const Constant(3600);
    final flaggedHours =
        lineItems.flaggedSeconds.cast<double>() / const Constant(3600);
    final billedAmount = billedHours * lineItems.unitPrice;

    final query = select(categories).join([
      leftOuterJoin(
        lineItems,
        lineItems.categoryId.equalsExp(categories.id) &
            lineItems.type.equals('labor') &
            lineItems.createdAt.isBetweenValues(from, to),
      ),
    ]);

    query
      ..addColumns([
        billedAmount.sum(),
        flaggedHours.sum(),
      ])
      ..groupBy([categories.id]);

    final rows = await query.get();
    return rows.map((row) {
      final category = row.readTable(categories);
      final totalBilled = row.read(billedAmount.sum()) ?? 0.0;
      final totalFlagged = row.read(flaggedHours.sum()) ?? 0.0;
      return CategoryRate(
        categoryId: category.id,
        categoryName: category.name,
        billedAmount: totalBilled,
        flaggedHours: totalFlagged,
      );
    }).toList();
  }
}

class CategoryRate {
  final int categoryId;
  final String categoryName;
  final double billedAmount;
  final double flaggedHours;

  const CategoryRate({
    required this.categoryId,
    required this.categoryName,
    required this.billedAmount,
    required this.flaggedHours,
  });

  double get realizedHourlyRate =>
      flaggedHours == 0 ? 0 : billedAmount / flaggedHours;
}

LazyDatabase _openConnection() {
  return LazyDatabase(() async {
    final Directory dir = await getApplicationDocumentsDirectory();
    final file = File(p.join(dir.path, 'marineflow.sqlite'));
    return NativeDatabase(file);
  });
}
