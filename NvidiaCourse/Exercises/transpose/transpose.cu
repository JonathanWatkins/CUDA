/*
 * Copyright 1993-2007 NVIDIA Corporation.  All rights reserved.
 *
 * NOTICE TO USER:
 *
 * This source code is subject to NVIDIA ownership rights under U.S. and
 * international Copyright laws.  Users and possessors of this source code
 * are hereby granted a nonexclusive, royalty-free license to use this code
 * in individual and commercial software.
 *
 * NVIDIA MAKES NO REPRESENTATION ABOUT THE SUITABILITY OF THIS SOURCE
 * CODE FOR ANY PURPOSE.  IT IS PROVIDED "AS IS" WITHOUT EXPRESS OR
 * IMPLIED WARRANTY OF ANY KIND.  NVIDIA DISCLAIMS ALL WARRANTIES WITH
 * REGARD TO THIS SOURCE CODE, INCLUDING ALL IMPLIED WARRANTIES OF
 * MERCHANTABILITY, NONINFRINGEMENT, AND FITNESS FOR A PARTICULAR PURPOSE.
 * IN NO EVENT SHALL NVIDIA BE LIABLE FOR ANY SPECIAL, INDIRECT, INCIDENTAL,
 * OR CONSEQUENTIAL DAMAGES, OR ANY DAMAGES WHATSOEVER RESULTING FROM LOSS
 * OF USE, DATA OR PROFITS,  WHETHER IN AN ACTION OF CONTRACT, NEGLIGENCE
 * OR OTHER TORTIOUS ACTION,  ARISING OUT OF OR IN CONNECTION WITH THE USE
 * OR PERFORMANCE OF THIS SOURCE CODE.
 *
 * U.S. Government End Users.   This source code is a "commercial item" as
 * that term is defined at  48 C.F.R. 2.numIterations1 (OCT 1995), consisting  of
 * "commercial computer  software"  and "commercial computer software
 * documentation" as such terms are  used in 48 C.F.R. 12.212 (SEPT 1995)
 * and is provided to the U.S. Government only as a commercial end item.
 * Consistent with 48 C.F.R.12.212 and 48 C.F.R. 227.7202-1 through
 * 227.7202-4 (JUNE 1995), all U.S. Government End Users acquire the
 * source code with only those rights set forth herein.
 *
 * Any use of this source code in individual and commercial software must
 * include, in the user documentation and internal comments to the code,
 * the above Disclaimer and U.S. Government End Users Notice.
 */
 
/* Matrix transpose with Cuda 
 * Host code.

 * This example transposes arbitrary-size matrices.  It compares a naive
 * transpose kernel that suffers from non-coalesced writes, to an optimized
 * transpose with fully coalesced memory access and no bank conflicts.  On 
 * a G80 GPU, the optimized transpose can be more than 10x faster for large
 * matrices.
 */

// includes, system
#include <stdlib.h>
#include <stdio.h>
#include <string.h>
#include <math.h>

// includes, project
#include <cutil_inline.h>

#define BLOCK_DIM 16

// This kernel is optimized to ensure all global reads and writes are coalesced,
// and to avoid bank conflicts in shared memory.  This kernel is up to 11x faster
// than the naive kernel below.  Note that the shared memory array is sized to 
// (BLOCK_DIM+1)*BLOCK_DIM.  This pads each row of the 2D block in shared memory 
// so that bank conflicts do not occur when threads address the array column-wise.
__global__ void transpose(float *odata, float *idata, int width, int height)
{
	__shared__ float block[BLOCK_DIM][BLOCK_DIM+1];
	
	// read the matrix tile into shared memory
        // load one element per thread from device memory (idata) and store it
        // in transposed order in block[][]
	unsigned int xIndex = blockIdx.x * BLOCK_DIM + threadIdx.x;
	unsigned int yIndex = blockIdx.y * BLOCK_DIM + threadIdx.y;
	if((xIndex < width) && (yIndex < height))
	{
		unsigned int index_in = yIndex * width + xIndex;
		block[threadIdx.y][threadIdx.x] = idata[index_in];
	}

        // synchronise to ensure all writes to block[][] have completed
	__syncthreads();

	// write the transposed matrix tile to global memory (odata) in linear order
	xIndex = blockIdx.y * BLOCK_DIM + threadIdx.x;
	yIndex = blockIdx.x * BLOCK_DIM + threadIdx.y;
	if((xIndex < height) && (yIndex < width))
	{
		unsigned int index_out = yIndex * height + xIndex;
		odata[index_out] = block[threadIdx.x][threadIdx.y];
	}
}


// This naive transpose kernel suffers from completely non-coalesced writes.
// It can be up to 10x slower than the kernel above for large matrices.
__global__ void transpose_naive(float *odata, float* idata, int width, int height)
{
   unsigned int xIndex = blockDim.x * blockIdx.x + threadIdx.x;
   unsigned int yIndex = blockDim.y * blockIdx.y + threadIdx.y;
   
   if (xIndex < width && yIndex < height)
   {
       unsigned int index_in  = xIndex + width * yIndex;
       unsigned int index_out = yIndex + height * xIndex;
       odata[index_out] = idata[index_in]; 
   }
}

////////////////////////////////////////////////////////////////////////////////
// declaration, forward
void runTest( int argc, char** argv);
extern "C" void computeGold( float* reference, float* idata, 
                         const unsigned int size_x, const unsigned int size_y );

////////////////////////////////////////////////////////////////////////////////
// Program main
////////////////////////////////////////////////////////////////////////////////
int
main( int argc, char** argv) 
{
    runTest( argc, argv);

    cutilExit(argc, argv);
}

////////////////////////////////////////////////////////////////////////////////
//! Run a simple test for CUDA
////////////////////////////////////////////////////////////////////////////////
void
runTest( int argc, char** argv) 
{
    // size of the matrix
#ifdef __DEVICE_EMULATION__
    const unsigned int size_x = 32;
    const unsigned int size_y = 128;
#else
    const unsigned int size_x = 256;
    const unsigned int size_y = 4096;
#endif
    // size of memory required to store the matrix
    const unsigned int mem_size = sizeof(float) * size_x * size_y;
    
    unsigned int timer;
    cutCreateTimer(&timer);

    // use command-line specified CUDA device, otherwise use device with highest Gflops/s
  	if( cutCheckCmdLineFlag(argc, (const char**)argv, "device") )
  		cutilDeviceInit(argc, argv);
  	else
  		cudaSetDevice( cutGetMaxGflopsDeviceId() );

    // allocate host memory
    float* h_idata = (float*) malloc(mem_size);
    // initalize the memory
    srand(15235911);
    for( unsigned int i = 0; i < (size_x * size_y); ++i) 
    {
        h_idata[i] = (float) i;    // rand(); 
    }

    // allocate device memory
    float* d_idata;
    float* d_odata;
    cutilSafeCall( cudaMalloc( (void**) &d_idata, mem_size));
    cutilSafeCall( cudaMalloc( (void**) &d_odata, mem_size));

    // copy host memory to device
    cutilSafeCall( cudaMemcpy( d_idata, h_idata, mem_size,
                                cudaMemcpyHostToDevice) );

    // setup execution parameters
    dim3 grid(size_x / BLOCK_DIM, size_y / BLOCK_DIM, 1);
    dim3 threads(BLOCK_DIM, BLOCK_DIM, 1);

    // warmup so we don't time CUDA startup
    transpose_naive<<< grid, threads >>>(d_odata, d_idata, size_x, size_y);
    transpose<<< grid, threads >>>(d_odata, d_idata, size_x, size_y);

	// synchronize here, so we make sure that we don't count any time from the asynchronize kernel launches.
	cudaThreadSynchronize();

    int numIterations = 1;

    printf("Transposing a %d by %d matrix of floats...\n", size_x, size_y);

    // execute the kernel
    cutStartTimer(timer);
    for (int i = 0; i < numIterations; ++i)
    {
        transpose_naive<<< grid, threads >>>(d_odata, d_idata, size_x, size_y);
    }
    cudaThreadSynchronize();
    cutStopTimer(timer);
    float naiveTime = cutGetTimerValue(timer);

    // execute the kernel
    
    cutResetTimer(timer);
    cutStartTimer(timer);
    for (int i = 0; i < numIterations; ++i)
    {
        transpose<<< grid, threads >>>(d_odata, d_idata, size_x, size_y);
    }
    cudaThreadSynchronize();
    cutStopTimer(timer);
    float optimizedTime = cutGetTimerValue(timer);

    printf("Naive transpose average time:     %0.3f ms\n", naiveTime / numIterations);
    printf("Optimized transpose average time: %0.3f ms\n\n", optimizedTime / numIterations);

    // check if kernel execution generated and error
    cutilCheckMsg("Kernel execution failed");

    // copy result from device to    host
    float* h_odata = (float*) malloc(mem_size);
    cutilSafeCall( cudaMemcpy( h_odata, d_odata, mem_size,
                                cudaMemcpyDeviceToHost) );

    // compute reference solution
    float* reference = (float*) malloc( mem_size);

    computeGold( reference, h_idata, size_x, size_y);

    // check result
    CUTBoolean res = cutComparef( reference, h_odata, size_x * size_y);
    printf(    "Test %s\n", (1    == res)    ? "PASSED" : "FAILED");

    // cleanup memory
    free(h_idata);
    free(h_odata);
    free( reference);
    cutilSafeCall(cudaFree(d_idata));
    cutilSafeCall(cudaFree(d_odata));
    cutilCheckError( cutDeleteTimer(timer));

    cudaThreadExit();
}
