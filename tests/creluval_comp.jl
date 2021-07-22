using VerifyDNN, LazySets, Test, LinearAlgebra, GLPK

nnet = read_nnet("/home/shchae7/VerifyDNN.jl/networks/small_nnet.nnet")
input_set  = Hyperrectangle(low = [-1.0], high = [1.0])
output_set = Hyperrectangle(low = [-1.0], high = [70.0])
problem = Problem(nnet, input_set, output_set)

println("ReluVal")
solver1 = ReluVal()
result1 = solve(solver1, problem)
println(result1)

println("CReluVal")
solver2 = CReluVal()
result2 = solve(solver2, problem)
println(result2)