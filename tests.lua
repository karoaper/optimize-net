local optnet = require 'optnet.env'
local models = require 'optnet.models'

local use_cudnn = false

if use_cudnn then
  require 'cudnn'
  require 'cunn'
end

local countUsedMemory = optnet.countUsedMemory

local optest = torch.TestSuite()
local tester = torch.Tester()

local function genericTestForward(model,opts)
  local net, input = models[model](opts)
  net:evaluate()
  
  if use_cudnn then
    cudnn.convert(net,cudnn);
    net:cuda();

    local function resizeAndConvert(input)
      local res
      if torch.isTensor(input) then
        local iSize = torch.Tensor(input:size():totable())[{{2,-1}}]
        res = torch.rand(128,table.unpack(iSize:totable())):cuda()
      else
        res = {}
        for k, v in ipairs(input) do
          res[k] = resizeAndConvert(v)
        end
      end
      return res
    end
    input = resizeAndConvert(input)
  end

  local out_orig = net:forward(input):clone()

  local mems1 = optnet.countUsedMemory(net, input)

  optnet.optimizeMemory(net, input)

  local out = net:forward(input):clone()
  local mems2 = countUsedMemory(net, input)
  tester:eq(out_orig, out, 'Outputs differ after optimization of '..model)

  local mem1 = mems1.total_size
  local mem2 = mems2.total_size

  local omem1 = mems1.outputs
  local omem2 = mems2.outputs

  local bmem1 = mems1.buffers
  local bmem2 = mems2.buffers

  local pmem1 = mems1.params
  local pmem2 = mems2.params

  tester:assertle(mem2, mem1, 'Optimized model uses more memory! '..
  'Before: '.. mem1..' bytes, After: '..mem2..' bytes')
  print('Memory use')
  print('Total',  mem1/1024/1024,  mem2/1024/1024, 1-mem2/mem1)
  print('Outputs',omem1/1024/1024,omem2/1024/1024, 1-omem2/omem1)
  print('Buffers',bmem1/1024/1024,bmem2/1024/1024, 1-bmem2/bmem1)
  print('Params', pmem1/1024/1024,pmem2/1024/1024, 1-pmem2/pmem1)
end
--[[
function optest.basic()
  genericTestForward('basic1')
end

function optest.basic_conv()
  genericTestForward('basic2')
end

function optest.basic_concat()
  genericTestForward('basic_concat')
end

function optest.alexnet()
  genericTestForward('alexnet')
end

function optest.googlenet()
  genericTestForward('googlenet')
end

function optest.vgg()
  genericTestForward('vgg')
end

function optest.resnet20()
  local opts = {dataset='cifar10',depth=20}
  genericTestForward('resnet', opts)
end

function optest.resnet32()
  local opts = {dataset='cifar10',depth=32}
  genericTestForward('resnet', opts)
end

function optest.resnet56()
  local opts = {dataset='cifar10',depth=56}
  genericTestForward('resnet', opts)
end

function optest.resnet110()
  local opts = {dataset='cifar10',depth=110}
  genericTestForward('resnet', opts)
end
--]]

-------------------------------------------------
-- Backward
-------------------------------------------------

-- reuse this function
local function recursiveClone(out)
  if torch.isTensor(out) then
    return out:clone()
  else
    local res = {}
    for k, v in ipairs(out) do
      res[k] = recursiveClone(v)
    end
  end
end


local function genericTestBackward(model,opts)
  local net, input = models[model](opts)
  net:training()

  local out_orig = recursiveClone(net:forward(input))
  local grad_orig = recursiveClone(out_orig)
  net:zeroGradParameters()
  local gradInput_orig = recursiveClone(net:backward(input, grad_orig))
  local _, gradParams_orig = net:getParameters()
  gradParams_orig = gradParams_orig:clone()

  local mems1 = optnet.countUsedMemory(net, input)

  optnet.optimizeMemory(net, input, {mode='training'})

  local out = recursiveClone(net:forward(input))
  local grad = recursiveClone(out)
  net:zeroGradParameters()
  local gradInput = recursiveClone(net:backward(input, grad))
  local _, gradParams = net:getParameters()
  gradParams = gradParams:clone()

  local mems2 = countUsedMemory(net, input)
  tester:eq(out_orig, out, 'Outputs differ after optimization of '..model)
  tester:eq(gradInput_orig, gradInput, 'GradInputs differ after optimization of '..model)
  tester:eq(gradParams_orig, gradParams, 'GradParams differ after optimization of '..model)

  local mem1 = mems1.total_size
  local mem2 = mems2.total_size

  local omem1 = mems1.outputs
  local omem2 = mems2.outputs

  local imem1 = mems1.gradInputs
  local imem2 = mems2.gradInputs

  local bmem1 = mems1.buffers
  local bmem2 = mems2.buffers

  local pmem1 = mems1.params
  local pmem2 = mems2.params

  tester:assertle(mem2, mem1, 'Optimized model uses more memory! '..
  'Before: '.. mem1..' bytes, After: '..mem2..' bytes')
  print('Memory use')
  print('Total',  mem1/1024/1024,  mem2/1024/1024, 1-mem2/mem1)
  print('Outputs',omem1/1024/1024,omem2/1024/1024, 1-omem2/omem1)
  print('gradInputs',imem1/1024/1024,imem2/1024/1024, 1-imem2/imem1)
  print('Buffers',bmem1/1024/1024,bmem2/1024/1024, 1-bmem2/bmem1)
  print('Params', pmem1/1024/1024,pmem2/1024/1024, 1-pmem2/pmem1)
end

function optest.basic_backward()
  genericTestBackward('basic1')
end

function optest.basic_conv_backward()
  genericTestBackward('basic2')
end

function optest.basic_conv2_backward()
  genericTestBackward('basic3')
end

function optest.basic_concat_backward()
  genericTestBackward('basic_concat')
end

function optest.alexnet_backward()
  --genericTestBackward('alexnet')
end

function optest.googlenet_backward()
  genericTestBackward('googlenet')
end


function optest.resnet20_backward()
  local opts = {dataset='cifar10',depth=20}
  genericTestBackward('resnet', opts)
end

function optest.resnet32_backward()
  local opts = {dataset='cifar10',depth=32}
  genericTestBackward('resnet', opts)
end

function optest.resnet56_backward()
  local opts = {dataset='cifar10',depth=56}
  genericTestBackward('resnet', opts)
end


tester:add(optest)

function optnet.test(tests)
  tester:run(tests)
  return tester
end
