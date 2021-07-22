@with_kw struct CReluVal <: Solver
    max_iter::Int64 = 100
    optimizer = GLPK.Optimizer

    node_split_select_heuristic = :NAIVE
    domain_select_heuristic = :DFS
end

function solve(solver::CReluVal, problem::Problem)
    # Array of domains after node split
    domain_list = []
    # Initial domain (0 splits done)
    domain = init_domain(problem.input)

    for i in 1:solver.max_iter
        if i > 1
            domain = domain_select!(domain_list, solver.domain_select_heuristic)
        end

        # Propagate input
        reach = forward_network(solver, problem.network, init_symbolic_mask(domain))

        # Check satisfiability of current domain
        result = check_satisfiability(solver, reach, problem.network, problem.output)

        #check_result(result)
        if result.status === :violated
            return result
        elseif result.status === :unknown
            subdomains = node_split_refinement(problem.network, reach, domain_list, solver.node_split_select_heuristic)
            add_subdomains!(subdomains, domain_list)
        end

        isempty(domain_list) && return CounterExampleResult(:holds)
    end

    return CounterExampleResult(:unknown)
end

function init_domain(input)
    return input
end

function domain_select!(domain_list, select_heuristic)
    if select_heuristic == :BFS
        domain = popfirst!(domain_list)
    elseif select_heuristic == :DFS
        domain = pop!(domain_list)
    else
        throw(ArgumentError(":$select_heuristic is not a valid tree search strategy"))
    end

    return domain
end

function check_satisfiability(solver, reach, nnet::Network, output)
    return check_inclusion(reach.sym, output, nnet)
end

function add_subdomains!(subdomains, domain_list)
    append!(domain_list, subdomains)
end

function node_split_refinement(nnet::Network, reach, domain_list, split_heuristic)
    LG, UG = get_gradient_bounds(nnet, reach.LΛ, reach.UΛ)
    feature, monotone = get_max_smear_index(nnet, reach.sym.domain, LG, UG) #monotonicity not used in this implementation.
    return collect(split_interval(reach.sym.domain, feature))
end

function check_inclusion(reach::SymbolicInterval{<:Hyperrectangle}, output, nnet::Network)
    reachable = Hyperrectangle(low = low(reach), high = high(reach))

    issubset(reachable, output) && return CounterExampleResult(:holds)

    # Sample the middle point
    middle_point = center(domain(reach))
    y = compute_output(nnet, middle_point)
    y ∈ output || return CounterExampleResult(:violated, middle_point)

    return CounterExampleResult(:unknown)
end

# Symbolic forward_linear
function forward_linear(solver::CReluVal, L::Layer, input::SymbolicIntervalMask)
    output_Low, output_Up = interval_map(L.weights, input.sym.Low, input.sym.Up)
    output_Up[:, end] += L.bias
    output_Low[:, end] += L.bias
    sym = SymbolicInterval(output_Low, output_Up, domain(input))
    return SymbolicIntervalGradient(sym, input.LΛ, input.UΛ)
end

# Symbolic forward_act
function forward_act(::CReluVal, L::Layer{ReLU},  input::SymbolicIntervalMask)
    output_Low, output_Up = copy(input.sym.Low), copy(input.sym.Up)
    n_node = n_nodes(L)
    LΛᵢ, UΛᵢ = falses(n_node), trues(n_node)

    for j in 1:n_node
        # If the upper bound of the upper bound is negative, set
        # the generators and centers of both bounds to 0, and
        # the gradient mask to 0
        if upper_bound(upper(input), j) <= 0
            LΛᵢ[j], UΛᵢ[j] = 0, 0
            output_Low[j, :] .= 0
            output_Up[j, :] .= 0

        # If the lower bound of the lower bound is positive,
        # the gradient mask should be 1
        elseif lower_bound(lower(input), j) >= 0
            LΛᵢ[j], UΛᵢ[j] = 1, 1

        # if the bounds overlap 0, concretize by setting
        # the generators to 0, and setting the new upper bound
        # center to be the current upper-upper bound.
        else
            LΛᵢ[j], UΛᵢ[j] = 0, 1
            output_Low[j, :] .= 0
            if lower_bound(upper(input), j) < 0
                output_Up[j, :] .= 0
                output_Up[j, end] = upper_bound(upper(input), j)
            end
        end
    end

    sym = SymbolicInterval(output_Low, output_Up, domain(input))
    LΛ = push!(input.LΛ, LΛᵢ)
    UΛ = push!(input.UΛ, UΛᵢ)
    return SymbolicIntervalGradient(sym, LΛ, UΛ)
end

# Symbolic forward_act
function forward_act(::CReluVal, L::Layer{Id}, input::SymbolicIntervalMask)
    n_node = size(input.sym.Up, 1)
    LΛ = push!(input.LΛ, trues(n_node))
    UΛ = push!(input.UΛ, trues(n_node))
    return SymbolicIntervalGradient(input.sym, LΛ, UΛ)
end

function get_max_smear_index(nnet::Network, input::Hyperrectangle, LG::Matrix, UG::Matrix)

    smear(lg, ug, r) = sum(max.(abs.(lg), abs.(ug))) * r

    ind = argmax(smear.(eachcol(LG), eachcol(UG), input.radius))
    monotone = all(>(0), LG[:, ind] .* UG[:, ind]) # NOTE should it be >= 0 instead?

    return ind, monotone
end
