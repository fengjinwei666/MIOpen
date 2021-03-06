/*******************************************************************************
 *
 * MIT License
 *
 * Copyright (c) 2018 Advanced Micro Devices, Inc.
 *
 * Permission is hereby granted, free of charge, to any person obtaining a copy
 * of this software and associated documentation files (the "Software"), to deal
 * in the Software without restriction, including without limitation the rights
 * to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
 * copies of the Software, and to permit persons to whom the Software is
 * furnished to do so, subject to the following conditions:
 *
 * The above copyright notice and this permission notice shall be included in all
 * copies or substantial portions of the Software.
 *
 * THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
 * IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
 * FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
 * AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
 * LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
 * OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
 * SOFTWARE.
 *
 *******************************************************************************/
#define PPCAT_NX(A, B) A##B
#define PPCAT(A, B) PPCAT_NX(A, B)
#define TWO 2
#define FOUR 4
#define EIGHT 8

#if(MIOPEN_USE_FP16 == 1 && MIOPEN_USE_FPMIX == 0)
#pragma OPENCL EXTENSION cl_khr_fp16 : enable
#define _FLOAT half
#define _FLOAT_PREC half
#ifndef HALF_MAX
#define MAX_VAL 65504 /* max value */
#else
#define MAX_VAL HALF_MAX
#endif
#define EPSILON (_FLOAT_PREC)0.0001
#elif(MIOPEN_USE_FP32 == 1 && MIOPEN_USE_FPMIX == 0)
#define _FLOAT float
#define _FLOAT_PREC float
#ifndef FLT_MAX
#define MAX_VAL 3.402823466e+38F /* max value */
#else
#define MAX_VAL FLT_MAX
#endif
#define EPSILON (_FLOAT)0.000001
#elif MIOPEN_USE_FPMIX == 1
#pragma OPENCL EXTENSION cl_khr_fp16 : enable
#define _FLOAT half
#define _FLOAT_PREC float
#define EPSILON (_FLOAT)0.000001
#endif

#define _FLOAT2 PPCAT(_FLOAT, TWO)
#define _FLOAT4 PPCAT(_FLOAT, FOUR)
#define _FLOAT8 PPCAT(_FLOAT, EIGHT)
#define _AS_FLOAT PPCAT(as_, _FLOAT)
#define UNUSED __attribute__((__unused__))

#define MIOPEN_NEURON_PASTHRU 0      // x
#define MIOPEN_NEURON_LOGISTIC 1     // 1 / (1 + e^-x)	//Sigmoid
#define MIOPEN_NEURON_TANH 2         // beta * tanh(alpha * x)
#define MIOPEN_NEURON_RELU 3         // max(0, x)
#define MIOPEN_NEURON_SOFTRELU 4     // log(1 + e^x)   // bonomial normal log likelihood
#define MIOPEN_NEURON_ABS 5          // abs(x)
#define MIOPEN_NEURON_POWER 6        // (alpha + beta * x )^gamma
#define MIOPEN_NEURON_CLIPPED_RELU 7 // min(alpha, max(0, x))
#define MIOPEN_NEURON_LEAKY_RELU 8   // alpha * x | x <= 0; x | x > 0
#define MIOPEN_NEURON_ELU 9          // alpha * (e^x - 1) | x <= 0; x | x > 0
//#define MIOPEN_NEURON_SQUARE 10      // x^2
//#define MIOPEN_NEURON_SQR 11         // sqr(x)
#define MIOPEN_NEURON_TOTAL 10

static __constant _FLOAT_PREC kBNLL_THRESHOLD = (_FLOAT_PREC)50.;

#ifndef MIO_BN_LDS_SIZE
#define MIO_BN_LDS_SIZE 1
#endif

#ifndef MIO_BN_C
#define MIO_BN_C 1
#endif

#ifndef MIO_BN_N
#define MIO_BN_N 1
#endif

#ifndef MIO_BN_NHW
#define MIO_BN_NHW 1
#endif

#ifndef MIO_BN_CHW
#define MIO_BN_CHW 1
#endif

#ifndef MIO_BN_INHW
#define MIO_BN_INHW 1
#endif

#ifndef MIO_BN_HW
#define MIO_BN_HW 1
#endif

#ifndef MIO_BN_NCHW
#define MIO_BN_NCHW 1
#endif

#ifndef MIO_BN_NODPP
#define MIO_BN_NODPP 0
#elif(MIO_BN_NODPP == 1)
#undef __AMDGCN__
#endif

/*#ifdef __AMDGCN__
#undef __AMDGCN__
#endif*/

// Disable specific warnings

#ifdef __clang__
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wconditional-uninitialized"
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wsometimes-uninitialized"
#endif

/******************************************************************************/
/*                                  DIFF                                      */
/******************************************************************************/
__attribute__((always_inline)) void
ActivationFunction_PassThru_Diff(const uint n,
                                 _FLOAT_PREC* bot_diff,
                                 const _FLOAT_PREC* top_diff,
                                 UNUSED const _FLOAT_PREC* bot_data,
                                 UNUSED const _FLOAT_PREC* top_data,
                                 UNUSED const _FLOAT_PREC diff_scale,
                                 UNUSED const _FLOAT_PREC gamma,
                                 UNUSED const _FLOAT_PREC beta,
                                 UNUSED const _FLOAT_PREC alpha)
{
    for(uint i = 0; i < n; ++i)
    {
        bot_diff[i] = top_diff[i];
    }
}

__attribute__((always_inline)) void
ActivationFunction_ReLU_Diff(const uint n,
                             _FLOAT_PREC* bot_diff,
                             const _FLOAT_PREC* top_diff,
                             const _FLOAT_PREC* bot_data,
                             UNUSED const _FLOAT_PREC* top_data,
                             UNUSED const _FLOAT_PREC diff_scale,
                             UNUSED const _FLOAT_PREC gamma,
                             UNUSED const _FLOAT_PREC beta,
                             UNUSED const _FLOAT_PREC alpha)
{
    for(uint i = 0; i < n; ++i)
    {
        bot_diff[i] = top_diff[i] * (bot_data[i] > 0);
    }
}

__attribute__((always_inline)) void
ActivationFunction_TanH_Diff(const uint n,
                             _FLOAT_PREC* bot_diff,
                             const _FLOAT_PREC* top_diff,
                             UNUSED const _FLOAT_PREC* bot_data,
                             const _FLOAT_PREC* top_data,
                             UNUSED const _FLOAT_PREC diff_scale,
                             UNUSED const _FLOAT_PREC gamma,
                             const _FLOAT_PREC beta,
                             const _FLOAT_PREC alpha)
{
    for(uint i = 0; i < n; ++i)
    {
        // dy/dx = alpha * (beta - y^2 / beta)
        _FLOAT_PREC y = top_data[i];
        bot_diff[i] =
            fabs(beta) <= EPSILON ? (_FLOAT_PREC)0 : (top_diff[i] * alpha * (beta - y * y / beta));
    }
}

__attribute__((always_inline)) void
ActivationFunction_Sigmoid_Diff(const uint n,
                                _FLOAT_PREC* bot_diff,
                                const _FLOAT_PREC* top_diff,
                                UNUSED const _FLOAT_PREC* bot_data,
                                const _FLOAT_PREC* top_data,
                                UNUSED const _FLOAT_PREC diff_scale,
                                UNUSED const _FLOAT_PREC gamma,
                                UNUSED const _FLOAT_PREC beta,
                                UNUSED const _FLOAT_PREC alpha)
{
    for(uint i = 0; i < n; ++i)
    {
        // y = 1/(1 + exp(-x))
        _FLOAT_PREC sigmoid_x = top_data[i];
        bot_diff[i]           = top_diff[i] * sigmoid_x * ((_FLOAT_PREC)1.f - sigmoid_x);
    }
}

__attribute__((always_inline)) void ActivationFunction_Abs_Diff(const uint n,
                                                                _FLOAT_PREC* bot_diff,
                                                                const _FLOAT_PREC* top_diff,
                                                                const _FLOAT_PREC* bot_data,
                                                                UNUSED const _FLOAT_PREC* top_data,
                                                                UNUSED const _FLOAT_PREC diff_scale,
                                                                UNUSED const _FLOAT_PREC gamma,
                                                                UNUSED const _FLOAT_PREC beta,
                                                                UNUSED const _FLOAT_PREC alpha)
{
    for(uint i = 0; i < n; ++i)
    {
        bot_diff[i] = top_diff[i] * ((bot_data[i] > 0) ? 1 : -1);
    }
}

// Compute dy/dx = beta * gamma * (alpha + beta * x)^(gamma - 1)
//               = diff_scale * y / (alpha + beta * x)
__attribute__((always_inline)) void
ActivationFunction_Power_Diff(const uint n,
                              _FLOAT_PREC* bot_diff,
                              UNUSED const _FLOAT_PREC* top_diff,
                              const _FLOAT_PREC* bot_data,
                              const _FLOAT_PREC* top_data,
                              const _FLOAT_PREC diff_scale,
                              UNUSED const _FLOAT_PREC gamma,
                              const _FLOAT_PREC beta,
                              const _FLOAT_PREC alpha)
{
    for(uint i = 0; i < n; ++i)
    {
        _FLOAT_PREC arg = alpha + bot_data[i] * beta;
        bot_diff[i]     = arg <= EPSILON ? (_FLOAT_PREC)0 : (diff_scale * top_data[i] / arg);
    }
}

__attribute__((always_inline)) void
ActivationFunction_BNLL_Diff(const uint n,
                             _FLOAT_PREC* bot_diff,
                             const _FLOAT_PREC* top_diff,
                             const _FLOAT_PREC* bot_data,
                             UNUSED const _FLOAT_PREC* top_data,
                             UNUSED const _FLOAT_PREC diff_scale,
                             UNUSED const _FLOAT_PREC gamma,
                             UNUSED const _FLOAT_PREC beta,
                             UNUSED const _FLOAT_PREC alpha)
{
    for(uint i = 0; i < n; ++i)
    {
        // y = (log(1 + exp(x)))
        // dy/dx = 1/ (1 + exp(-x))
        _FLOAT_PREC expval = exp(fmin(bot_data[i], kBNLL_THRESHOLD));
        bot_diff[i]        = top_diff[i] * expval / (expval + (_FLOAT_PREC)1.f);
    }
}

__attribute__((always_inline)) void
ActivationFunction_Leaky_ReLU_Diff(const uint n,
                                   _FLOAT_PREC* bot_diff,
                                   const _FLOAT_PREC* top_diff,
                                   const _FLOAT_PREC* bot_data,
                                   UNUSED const _FLOAT_PREC* top_data,
                                   UNUSED const _FLOAT_PREC diff_scale,
                                   UNUSED const _FLOAT_PREC gamma,
                                   UNUSED const _FLOAT_PREC beta,
                                   const _FLOAT_PREC alpha)
{
    for(uint i = 0; i < n; ++i)
    {
        bot_diff[i] = top_diff[i] * ((bot_data[i] > 0) ? (_FLOAT_PREC)1.f : alpha);
    }
}

__attribute__((always_inline)) void
ActivationFunction_Clipped_ReLU_Diff(const uint n,
                                     _FLOAT_PREC* bot_diff,
                                     const _FLOAT_PREC* top_diff,
                                     const _FLOAT_PREC* bot_data,
                                     UNUSED const _FLOAT_PREC* top_data,
                                     UNUSED const _FLOAT_PREC diff_scale,
                                     UNUSED const _FLOAT_PREC gamma,
                                     UNUSED const _FLOAT_PREC beta,
                                     const _FLOAT_PREC alpha)
{
    for(uint i = 0; i < n; ++i)
    {
        bot_diff[i] = top_diff[i] * ((bot_data[i] > 0 && bot_data[i] <= alpha) ? (_FLOAT_PREC)1.f
                                                                               : (_FLOAT_PREC)0.f);
    }
}

__attribute__((always_inline)) void ActivationFunction_ELU_Diff(const uint n,
                                                                _FLOAT_PREC* bot_diff,
                                                                const _FLOAT_PREC* top_diff,
                                                                const _FLOAT_PREC* bot_data,
                                                                const _FLOAT_PREC* top_data,
                                                                UNUSED const _FLOAT_PREC diff_scale,
                                                                UNUSED const _FLOAT_PREC gamma,
                                                                UNUSED const _FLOAT_PREC beta,
                                                                const _FLOAT_PREC alpha)
{
    for(uint i = 0; i < n; ++i)
    {
        bot_diff[i] = top_diff[i] * ((bot_data[i] > 0) ? 1 : top_data[i] + alpha);
    }
}

__attribute__((always_inline)) void ActivationFunction_Diff(const uint n,
                                                            _FLOAT_PREC* bot_diff,
                                                            const _FLOAT_PREC* top_diff,
                                                            const _FLOAT_PREC* bot_data,
                                                            const _FLOAT_PREC* top_data,
                                                            const _FLOAT_PREC diff_scale,
                                                            const _FLOAT_PREC gamma,
                                                            const _FLOAT_PREC beta,
                                                            const _FLOAT_PREC alpha)
{
#if MIOPEN_NRN_OP_ID == MIOPEN_NEURON_PASTHRU
    {
        ActivationFunction_PassThru_Diff(
            n, bot_diff, top_diff, bot_data, top_data, diff_scale, gamma, beta, alpha);
    }
#elif MIOPEN_NRN_OP_ID == MIOPEN_NEURON_LOGISTIC
    {
        // y = 1/(1 + exp(-x))
        ActivationFunction_Sigmoid_Diff(
            n, bot_diff, top_diff, bot_data, top_data, diff_scale, gamma, beta, alpha);
    }
#elif MIOPEN_NRN_OP_ID == MIOPEN_NEURON_TANH
    {
        // y = beta * tanh(alpha * x)
        ActivationFunction_TanH_Diff(
            n, bot_diff, top_diff, bot_data, top_data, diff_scale, gamma, beta, alpha);
    }
#elif MIOPEN_NRN_OP_ID == MIOPEN_NEURON_RELU
    {
        ActivationFunction_ReLU_Diff(
            n, bot_diff, top_diff, bot_data, top_data, diff_scale, gamma, beta, alpha);
    }
#elif MIOPEN_NRN_OP_ID == MIOPEN_NEURON_SOFTRELU
    {
        // y = log(1 + exp(x))
        ActivationFunction_BNLL_Diff(
            n, bot_diff, top_diff, bot_data, top_data, diff_scale, gamma, beta, alpha);
    }
#elif MIOPEN_NRN_OP_ID == MIOPEN_NEURON_ABS
    {
        ActivationFunction_Abs_Diff(
            n, bot_diff, top_diff, bot_data, top_data, diff_scale, gamma, beta, alpha);
    }
#elif MIOPEN_NRN_OP_ID == MIOPEN_NEURON_POWER
    {
        // y = (alpha + beta * x ) ^ gamma
        ActivationFunction_Power_Diff(
            n, bot_diff, top_diff, bot_data, top_data, diff_scale, gamma, beta, alpha);
    }
#elif MIOPEN_NRN_OP_ID == MIOPEN_NEURON_CLIPPED_RELU
    {
        ActivationFunction_Clipped_ReLU_Diff(
            n, bot_diff, top_diff, bot_data, top_data, diff_scale, gamma, beta, alpha);
    }
#elif MIOPEN_NRN_OP_ID == MIOPEN_NEURON_LEAKY_RELU
    {
        ActivationFunction_Leaky_ReLU_Diff(
            n, bot_diff, top_diff, bot_data, top_data, diff_scale, gamma, beta, alpha);
    }
#elif MIOPEN_NRN_OP_ID == MIOPEN_NEURON_ELU
    {
        ActivationFunction_ELU_Diff(
            n, bot_diff, top_diff, bot_data, top_data, diff_scale, gamma, beta, alpha);
    }
#endif
}

__kernel void
MIOpenBatchNormActivBwdPerActivation(const __global _FLOAT* __restrict x_in,
                                     const __global _FLOAT* __restrict y_in,
                                     const __global _FLOAT* __restrict dy_in,
                                     __global _FLOAT* __restrict dx_out,
                                     _FLOAT diff_scale,
                                     _FLOAT gamma,
                                     _FLOAT beta,
                                     _FLOAT alpha,
                                     const __global _FLOAT_PREC* __restrict bnScale,
                                     const __global _FLOAT_PREC* __restrict bnBias,
                                     __global _FLOAT_PREC* __restrict dscale,
                                     __global _FLOAT_PREC* __restrict dbias,
                                     const __global _FLOAT_PREC* __restrict savedMean,
                                     const __global _FLOAT_PREC* __restrict savedInvVariance
#if MIO_BN_CBA_WRITE_INTERMEDIATE
                                     ,
                                     __global _FLOAT* __restrict bn_out_dev,
                                     __global _FLOAT* __restrict bn_dyin_dev
#endif
                                     )
{

    int xgid    = get_global_id(0);
    int ygid    = get_global_id(1);
    int yglb_sz = get_global_size(1);
    int Cidx    = MIO_BN_HW * xgid;

    unsigned int inImgIndex, index, adjIndex;
    _FLOAT_PREC mean, invVar;
    _FLOAT_PREC xhat, dyelem;
    _FLOAT_PREC pvt_scale, pvt_bias, pvt_dscale;
    _FLOAT_PREC pvt_dbias;
    _FLOAT_PREC tmp1, tmp2, tmp3;
    _FLOAT_PREC dxhat    = (_FLOAT_PREC)0.;
    _FLOAT_PREC dxhathat = (_FLOAT_PREC)0.;

    // move across the sections of an image in the mini_batch stack
    for(int img_offset = 0; img_offset < MIO_BN_HW; img_offset += yglb_sz)
    {

        inImgIndex = img_offset + ygid;
        if(inImgIndex < MIO_BN_HW)
        {

            adjIndex   = Cidx + inImgIndex; // gamma and beta tensor index
            mean       = savedMean[adjIndex];
            invVar     = savedInvVariance[adjIndex];
            pvt_scale  = bnScale[adjIndex];
            pvt_bias   = bnBias[adjIndex];
            pvt_dscale = (_FLOAT_PREC)0.;
            pvt_dbias  = (_FLOAT_PREC)0.;
            dxhat      = (_FLOAT_PREC)0.;
            dxhathat   = (_FLOAT_PREC)0.;

            for(int n = 0; n < MIO_BN_N; n++)
            {
                // per (x-dims) channel load a block of data into LDS
                index = MIO_BN_CHW * n + adjIndex;
                xhat  = ((_FLOAT_PREC)(*(x_in + index)) - mean) * invVar;
                // dyelem = dy_in[index];
                _FLOAT_PREC act_dyin = *(dy_in + index);
                _FLOAT_PREC act_out  = *(y_in + index);
                _FLOAT_PREC bn_out   = mad(xhat, pvt_scale, pvt_bias);
                _FLOAT_PREC bn_dyin;
                ActivationFunction_Diff(
                    1, &bn_dyin, &act_dyin, &bn_out, &act_out, diff_scale, gamma, beta, alpha);
#if MIO_BN_CBA_WRITE_INTERMEDIATE
                // for debugging
                bn_out_dev[index]  = bn_out;
                bn_dyin_dev[index] = bn_dyin;
#endif

                dyelem = bn_dyin;
                pvt_dbias += dyelem;
                pvt_dscale = mad(xhat, dyelem, pvt_dscale);
                tmp1       = pvt_scale * dyelem;
                dxhat += tmp1;
                dxhathat = mad(tmp1, xhat, dxhathat);
            } // end for(n)

            for(int n = 0; n < MIO_BN_N; n++)
            {
                index         = MIO_BN_CHW * n + adjIndex;
                xhat          = ((_FLOAT_PREC)(*(x_in + index)) - mean) * invVar;
                tmp1          = mad(xhat, dxhathat, dxhat);
                tmp2          = mad((_FLOAT_PREC)MIO_BN_N, dxhat, -tmp1);
                tmp3          = invVar / ((_FLOAT_PREC)MIO_BN_N);
                dx_out[index] = (_FLOAT)(tmp3 * tmp2);
            }
            // Write out data
            dbias[adjIndex]  = pvt_dbias;
            dscale[adjIndex] = pvt_dscale;
        }
    } // end for(img_offset) //image mini_batch is processed
}

// Restore warnings

#ifdef __clang__
#pragma clang diagnostic pop
#pragma clang diagnostic pop
#endif
