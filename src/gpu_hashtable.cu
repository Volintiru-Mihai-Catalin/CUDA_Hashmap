#include <iostream>
#include <limits.h>
#include <stdlib.h>
#include <string.h>
#include <stdio.h>
#include <ctime>
#include <sstream>
#include <string>
#include "test_map.hpp"
#include "gpu_hashtable.hpp"

using namespace std;

__device__ unsigned int transf_key_to_hash(int key, int sizeTable) {
	unsigned int hash = (unsigned int) key;
	
	hash ^= hash >> 16;
	hash *= K;
    hash ^= hash >> 13;
    hash *= M;
	hash ^= hash >> 16;

	return hash % sizeTable;
}

__device__ void insert_element(unsigned int starting_hash, int key, int value, hash_T table, int table_size) {
	unsigned int hash_key = starting_hash % table_size;
	bool inserted = false;

	while (!inserted) {
		int old_value = atomicCAS(&table[hash_key].key, 0, key);
		if (old_value == 0 || old_value == key) {
			table[hash_key].value = value;
			inserted = true;
		}
		hash_key++;
		hash_key = hash_key % table_size;
	}
}

__global__ void batch_insert(int *keys, int *values, int numKeys, hash_T table, int table_size) {
	
	unsigned int index = threadIdx.x + blockDim.x * blockIdx.x;

	if (index < numKeys) {
		unsigned int hash_key = transf_key_to_hash(keys[index], table_size);
		insert_element(hash_key, keys[index], values[index], table, table_size);
	}

}

__global__ void transfer_elements(hash_T new_hash_map, int new_size, hash_T old_hash_map, int old_size) {

	unsigned int index = threadIdx.x + blockDim.x * blockIdx.x;

	if (index < old_size && old_hash_map[index].key != 0) {
		unsigned int new_hash = transf_key_to_hash(old_hash_map[index].key, new_size);
		insert_element(new_hash, old_hash_map[index].key, old_hash_map[index].value, new_hash_map, new_size);
	}
}

__global__ void batch_find(int *keys, int *values, int numKeys, hash_T table, int table_size) {
	unsigned int index = threadIdx.x + blockDim.x * blockIdx.x;
	bool found = false;

	if (index < numKeys) {
		unsigned int hash_key = transf_key_to_hash(keys[index], table_size);
		while (!found) {
			if (table[hash_key].key == keys[index]) {
				values[index] = table[hash_key].value;
				found = true;
			}
			hash_key++;
			hash_key = hash_key % table_size;
		}
	}
}
/*
Allocate CUDA memory only through glbGpuAllocator
cudaMalloc -> glbGpuAllocator->_cudaMalloc
cudaMallocManaged -> glbGpuAllocator->_cudaMallocManaged
cudaFree -> glbGpuAllocator->_cudaFree
*/

/**
 * Function constructor GpuHashTable
 * Performs init
 * Example on using wrapper allocators _cudaMalloc and _cudaFree
 */
GpuHashTable::GpuHashTable(int size) {
	
	glbGpuAllocator->_cudaMalloc((void **) &this->hash_table, sizeof(hash_t) * size);
	cudaMemset(this->hash_table, 0, sizeof(hash_t) * size);
	
	this->hash_table_size = size;
	this->num_elem = 0;

	this->block_size = BLOCK_SIZE;
}

/**
 * Function desctructor GpuHashTable
 */
GpuHashTable::~GpuHashTable() {
	glbGpuAllocator->_cudaFree(this->hash_table);
}

/**
 * Function reshape
 * Performs resize of the hashtable based on load factor
 */
void GpuHashTable::reshape(int numBucketsReshape) {
	
	hash_T new_hash_table = 0;
	size_t block_no = hash_table_size / block_size;

	if (hash_table_size % block_size) {
		block_no++;
	}

	glbGpuAllocator->_cudaMalloc((void **) &new_hash_table, sizeof(hash_t) * numBucketsReshape);
	cudaMemset(new_hash_table, 0, sizeof(hash_t) * numBucketsReshape);

	transfer_elements<<<block_no, block_size>>>(new_hash_table, numBucketsReshape, hash_table, hash_table_size);
	cudaDeviceSynchronize();


	glbGpuAllocator->_cudaFree(this->hash_table);
	this->hash_table = new_hash_table;
	hash_table_size = numBucketsReshape;

	return;
}

/**
 * Function insertBatch
 * Inserts a batch of key:value, using GPU and wrapper allocators
 */
bool GpuHashTable::insertBatch(int *keys, int* values, int numKeys) {

	int *device_keys = 0;
	int *device_values = 0;
	size_t block_no = numKeys / block_size;
	
	if (numKeys % block_size) {
		block_no++;
	}
	
	glbGpuAllocator->_cudaMalloc((void **) &device_keys, sizeof(int) * numKeys);
	glbGpuAllocator->_cudaMalloc((void **) &device_values, sizeof(int) * numKeys);
	
	cudaMemcpy(device_keys, keys, sizeof(int) * numKeys, cudaMemcpyHostToDevice);
	cudaMemcpy(device_values, values, sizeof(int) * numKeys, cudaMemcpyHostToDevice);


	if ((num_elem + numKeys) / float(hash_table_size) > LOAD_FACTOR_HIGH) {
		reshape((int) ((num_elem + numKeys) / LOAD_FACTOR_LOW));
	}

	batch_insert<<<block_no, block_size>>>(device_keys, device_values, numKeys, this->hash_table, this->hash_table_size);
	cudaDeviceSynchronize();

	num_elem += numKeys;

	glbGpuAllocator->_cudaFree(device_keys);
	glbGpuAllocator->_cudaFree(device_values);

	return true;
}

/**
 * Function getBatch
 * Gets a batch of key:value, using GPU
 */
int* GpuHashTable::getBatch(int* keys, int numKeys) {

	int *host_values = 0;
	int *device_values = 0;
	int *device_keys = 0;
	size_t block_no = numKeys / block_size;

	if (numKeys % block_size) {
		block_no++;
	}
	
	glbGpuAllocator->_cudaMalloc((void **) &device_keys, sizeof(int) * numKeys);
	cudaMemcpy(device_keys, keys, sizeof(int) * numKeys, cudaMemcpyHostToDevice);

	glbGpuAllocator->_cudaMalloc((void **) &device_values, sizeof(int) * numKeys);
	host_values = (int *)malloc(sizeof(int) * numKeys);

	batch_find<<<block_no, block_size>>>(device_keys, device_values, numKeys, this->hash_table, this->hash_table_size);
	cudaDeviceSynchronize();

	cudaMemcpy(host_values, device_values, sizeof(int) * numKeys, cudaMemcpyDeviceToHost);

	glbGpuAllocator->_cudaFree(device_keys);
	glbGpuAllocator->_cudaFree(device_values);

	return host_values;
}
