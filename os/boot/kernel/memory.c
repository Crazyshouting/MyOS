#include "memory.h"
#include "bitmap.h"
#include "global.h"
#include "debug.h"
#include "stdint.h"
#include "print.h"
#include "string.h"

#define PG_SIZE 4096

#define MEM_BITMAP_BASE 0xc009a000
#define K_HEAP_START 0xc0100000
#define PED_IDX(addr) ((addr & 0xffc00000) >> 22)
#define PTE_IDX(addr) ((addr & 0x003ff000) >> 12)

struct pool
{
    struct bitmap pool_bitmap;
    uint32_t phy_addr_start;
    uint32_t pool_size;
};
struct pool kernel_pool, user_pool;
struct virtual_addr kernel_vadddr;

static void mem_pool_init(uint32_t all_mem){
    put_str("mem_pool_init start\n");
    uint32_t page_table_size = PG_SIZE * 256;   // 1 MB 0x100000
    uint32_t used_mem = page_table_size + 0x100000; // 1MB + 1MB，已使用2MB空间
    // 前 1 MB 
    uint32_t free_mem = all_mem - used_mem;
    uint16_t all_free_pages = free_mem / PG_SIZE;

    uint16_t kernel_free_pages = all_free_pages / 2;
    uint16_t user_free_pages = all_free_pages - kernel_free_pages;

    // kernel 和 user bitmap 的长度
    uint32_t kbm_length = kernel_free_pages / 8;
    uint32_t ubm_length = user_free_pages / 8;

    uint32_t kp_start = used_mem;
    uint32_t up_start = kp_start + kernel_free_pages * PG_SIZE;

    kernel_pool.phy_addr_start = kp_start;
    user_pool.phy_addr_start = up_start;

    kernel_pool.pool_size = kernel_free_pages * PG_SIZE;
    user_pool.pool_size = user_free_pages * PG_SIZE;

    kernel_pool.pool_bitmap.btmp_bytes_len = kbm_length;
    user_pool.pool_bitmap.btmp_bytes_len = ubm_length;

    kernel_pool.pool_bitmap.bits = (void *)MEM_BITMAP_BASE;             // 位图地址
    user_pool.pool_bitmap.bits = (void *)(MEM_BITMAP_BASE + kbm_length);

    put_str("kernel_pool_bitmap_start:");
    put_int((int)kernel_pool.pool_bitmap.bits);
    put_str("kernel_pool_phy_addr_start:");
    put_int(kernel_pool.phy_addr_start);
    put_str("\n");
    put_str("user_pool_bitmap_start:");
    put_int((int)user_pool.pool_bitmap.bits);
    put_str("user_pool_phy_addr_start:");
    put_int(user_pool.phy_addr_start);
    put_str("\n");

    bitmap_init(&kernel_pool.pool_bitmap);
    bitmap_init(&user_pool.pool_bitmap);

    kernel_vadddr.vaddr_bitmap.bits = (void*)(MEM_BITMAP_BASE+kbm_length+ubm_length);

    kernel_vadddr.vaddr_start = K_HEAP_START;
    bitmap_init(&kernel_vadddr.vaddr_bitmap);

    put_str("mem_pool_init done\n");
}

void mem_init(){
    put_str("mem_init start\n");
    uint32_t mem_bytes_total = (*(uint32_t*)(0xb00));
    mem_pool_init(mem_bytes_total);
    put_str("mem_init done\n");
}

static void* vaddr_get(enum pool_flags pf, uint32_t pg_cnt){
    int vaddr_start = 0, bit_idx_start = -1;
    uint32_t cnt = 0;
    if(pf == PF_KERNEL){ 
        //指定内核内存分配
        //首先找到一段连续的空间，页数满足pg_cnt，返回页数的下标
        bit_idx_start = bitmap_scan(&kernel_vadddr.vaddr_bitmap, pg_cnt);
        if(bit_idx_start == -1){
            return NULL;
        }
        while(cnt < pg_cnt){//找到后对应位图设置为已使用
            bitmap_set(&kernel_vadddr.vaddr_bitmap, bit_idx_start+cnt++, 1);
        }
        vaddr_start = kernel_vadddr.vaddr_start + bit_idx_start + PG_SIZE;
    }else{
        //用户内存分配
    }
    return (void*) vaddr_start;
}