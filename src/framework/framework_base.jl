@with_kw struct Verifier <: Solver
    max_iter::Int64 = 100
    optimizer = GLPK.Optimizer

    node_split_select_heuristic = :DFS
    domain_select_heuristic = :NAIVE
end

function solve(solver::Verifier, problem::Problem)
    # Array of domains after node split
    domain_list = []
    # Initial domain (0 splits done)
    domain = init_domain(problem.input)

    for i in 1:solver.max_iter
        if i > 1
            domain = domain_select!(domain_list, solver.domain_select_heuristic)
        end

        # Propagate input
        reach = forward_network(solver, problem.network, domain)

        # Check satisfiability of current domain
        result, = check_satisfiability(solver, reach, problem.network, problem.output)

        #check_result(result)
        if result.status === :violated
            return result
        elseif result.status === :unknown
            subdomains = node_split_refinement(problem.network, reach, domain_list, solver.node_split_select_heuristic)
            for domain in subdomains

            end
        end

        isempty(domain_list) && return CounterExampleResult(:holds)
    end

    return CounterExampleResult(:unknown)
end

function domain_select!(domain_list, select_heuristic)
    if select_heuristic == :BFS
        domain = popfirst!(domain_list)
    elseif select_heuristic == :DFS
        domain = pop!(domain_list)
    elseif select_heuristic == :NAIVE
        domain = ..
    else
        throw(ArgumentError(":$select_heuristic is not a valid tree search strategy"))
    end

    return domain
end

function node_split_refinement(nnet::Network, reach, domain_list, split_heuristic)
    if split_heuristic == :NAIVE
        return domain_list
    else
        return domain_list
    end
end

function check_satisfiability(solver, reach, nnet::Network, output)
    return CounterExampleResult(:unknown)
end