# 定向复现审查缺陷：必须通过 do 执行宏，ModelSim 才应用错误处理。
onerror {quit -code 1 -f}
onbreak {quit -code 1 -f}
run 5 ms
quit -code 0 -f
