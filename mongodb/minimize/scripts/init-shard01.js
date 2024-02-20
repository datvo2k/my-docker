rs.initiate({
  _id: "rs-shard-1",
  version: 1,
  members: [
    { _id: 0, host: "shard-1a:27017" },
    { _id: 1, host: "shard-1b:27017" },
    { _id: 2, host: "shard-1c:27017" },
  ],
});
