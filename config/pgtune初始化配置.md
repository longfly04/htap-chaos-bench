# PGTune 初始化配置

## 1. 4U4G postgresql.conf 配置

```bash
# WARNING
# wal_compression = lz4 requires PostgreSQL
# to be compiled with --with-lz4

# DB Version: 17
# OS Type: linux
# DB Type: mixed
# Total Memory (RAM): 4 GB
# CPUs num: 4
# Connections num: 500
# Data Storage: hdd

max_connections = 500
shared_buffers = 1GB
effective_cache_size = 3GB
maintenance_work_mem = 256MB
checkpoint_completion_target = 0.9
wal_buffers = 16MB
default_statistics_target = 100
random_page_cost = 4
effective_io_concurrency = 2
work_mem = 4MB
huge_pages = off
jit = off
wal_compression = lz4
min_wal_size = 1GB
max_wal_size = 4GB
max_worker_processes = 4
max_parallel_workers_per_gather = 2
max_parallel_workers = 4
max_parallel_maintenance_workers = 2
```

## 2. 4U8G postgresql.conf 配置

```bash
# WARNING
# wal_compression = lz4 requires PostgreSQL
# to be compiled with --with-lz4

# DB Version: 17
# OS Type: linux
# DB Type: mixed
# Total Memory (RAM): 8 GB
# CPUs num: 4
# Connections num: 500
# Data Storage: hdd

max_connections = 500
shared_buffers = 2GB
effective_cache_size = 6GB
maintenance_work_mem = 512MB
checkpoint_completion_target = 0.9
wal_buffers = 16MB
default_statistics_target = 100
random_page_cost = 4
effective_io_concurrency = 2
work_mem = 4MB
huge_pages = try
jit = off
wal_compression = lz4
min_wal_size = 1GB
max_wal_size = 4GB
max_worker_processes = 4
max_parallel_workers_per_gather = 2
max_parallel_workers = 4
max_parallel_maintenance_workers = 2
```

## 3. 8U8G postgresql.conf 配置
```bash
# WARNING
# wal_compression = lz4 requires PostgreSQL
# to be compiled with --with-lz4

# DB Version: 17
# OS Type: linux
# DB Type: mixed
# Total Memory (RAM): 8 GB
# CPUs num: 8
# Connections num: 500
# Data Storage: hdd

max_connections = 500
shared_buffers = 2GB
effective_cache_size = 6GB
maintenance_work_mem = 512MB
checkpoint_completion_target = 0.9
wal_buffers = 16MB
default_statistics_target = 100
random_page_cost = 4
effective_io_concurrency = 2
work_mem = 4MB
huge_pages = try
jit = off
wal_compression = lz4
min_wal_size = 1GB
max_wal_size = 4GB
max_worker_processes = 8
max_parallel_workers_per_gather = 4
max_parallel_workers = 8
max_parallel_maintenance_workers = 4
```

## 4. 8U16G postgresql.conf 配置

```bash
# WARNING
# wal_compression = lz4 requires PostgreSQL
# to be compiled with --with-lz4

# DB Version: 17
# OS Type: linux
# DB Type: mixed
# Total Memory (RAM): 16 GB
# CPUs num: 8
# Connections num: 500
# Data Storage: hdd

max_connections = 500
shared_buffers = 4GB
effective_cache_size = 12GB
maintenance_work_mem = 1GB
checkpoint_completion_target = 0.9
wal_buffers = 16MB
default_statistics_target = 100
random_page_cost = 4
effective_io_concurrency = 2
work_mem = 4MB
huge_pages = try
jit = off
wal_compression = lz4
min_wal_size = 1GB
max_wal_size = 4GB
max_worker_processes = 8
max_parallel_workers_per_gather = 4
max_parallel_workers = 8
max_parallel_maintenance_workers = 4