#ifndef _HASHCPU_
#define _HASHCPU_

#define LOAD_FACTOR_LOW 0.5f
#define LOAD_FACTOR_HIGH 0.9f
#define K 0x85ebca6b
#define M 0xc2b2ae35
#define BLOCK_SIZE 1024


/**
 * Struct HashTable to implement the hash table
 */
typedef struct HashTable {
	int key;
	int value;
} hash_t, *hash_T;

/**
 * Class GpuHashTable to implement functions
 */
class GpuHashTable
{
	public:
		hash_T hash_table = 0;
		int hash_table_size = 0;
		int num_elem = 0;
		size_t block_size;

		GpuHashTable(int size);
		void reshape(int sizeReshape);

		bool insertBatch(int *keys, int* values, int numKeys);
		int* getBatch(int* key, int numItems);

		~GpuHashTable();
};

#endif
