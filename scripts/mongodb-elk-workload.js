const testDb = db.getSiblingDB("observability_test");
const collection = testDb.getCollection("elk_validation");
const runId = `elk-${new Date().toISOString()}`;

// Log every operation during this short validation workload.
testDb.setProfilingLevel(1, { slowms: 0, sampleRate: 1 });

try {
  collection.createIndex({ run_id: 1, sequence: 1 });

  const documents = Array.from({ length: 200 }, (_, sequence) => ({
    run_id: runId,
    sequence,
    category: `category-${sequence % 5}`,
    amount: sequence * 10,
    processed: false,
    created_at: new Date(),
  }));

  const inserted = collection.insertMany(documents);

  collection.updateMany(
    { run_id: runId, sequence: { $lt: 100 } },
    { $set: { processed: true, processed_at: new Date() } },
  );

  collection
    .find({ run_id: runId, processed: true })
    .sort({ sequence: -1 })
    .limit(20)
    .toArray();

  const totals = collection
    .aggregate([
      { $match: { run_id: runId } },
      {
        $group: {
          _id: "$category",
          count: { $sum: 1 },
          total_amount: { $sum: "$amount" },
        },
      },
      { $sort: { _id: 1 } },
    ])
    .toArray();

  const deleted = collection.deleteMany({
    run_id: runId,
    sequence: { $gte: 190 },
  });

  printjson({
    run_id: runId,
    inserted: Object.keys(inserted.insertedIds).length,
    deleted: deleted.deletedCount,
    remaining: collection.countDocuments({ run_id: runId }),
    totals,
  });
} finally {
  testDb.setProfilingLevel(0);
}
