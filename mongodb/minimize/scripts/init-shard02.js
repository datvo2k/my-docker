rs.initiate({
  _id: "rs-shard-2",
  version: 1,
  members: [
    { _id: 0, host: "shard-2a:27017" },
    { _id: 1, host: "shard-2b:27017" },
    { _id: 2, host: "shard-2c:27017" },
  ],
});
