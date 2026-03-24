import numpy as np
from scipy.optimize import minimize


WBTC_RECEIVED = 94.27338222
USDC_TO_REPAY = 2916378.221684 + 0.000002 # Borrowed + fee (6 decimals)

# WBTC/WETH Pools
WETH_UNI = 38844.04247515448
WBTC_UNI = 2293.69102880
WETH_SUSHI = 88902.65047857448
WBTC_SUSHI = 5253.97180491

# WETH/DAI Pools (Path A)
WETH_DAI_UNI = 25620.28738677924
DAI_UNI = 51680858.4158025
WETH_DAI_SUSHI = 50672.98762891207
DAI_SUSHI = 102278491.801378

# WETH/USDC Pools (Path B)
WETH_USDC_UNI = 53146.03595102377
USDC_UNI = 107391732.922008
WETH_USDC_SUSHI = 82306.09980090123
USDC_SUSHI = 166057035.198029

CURVE_FEE = 0.0004

def getAmountIn(rIn, rOut, dy):
    if dy <= 0: return 0
    if dy >= rOut: return 1e18 # Prevent pool draining
    return (rIn * dy * 1000) / ((rOut - dy) * 997)

def getAmountOut(rIn, rOut, dx):
    if dx <= 0: return 0
    dxFee = dx * 997
    return (dxFee * rOut) / (rIn * 1000 + dxFee)


def optimize_wbtc_to_weth(total_wbtc):
    def objective(x):
        # x is amount of WBTC to Uni
        out_uni = getAmountOut(WBTC_UNI, WETH_UNI, x)
        out_sushi = getAmountOut(WBTC_SUSHI, WETH_SUSHI, total_wbtc - x)
        return -(out_uni + out_sushi) # Maximize WETH out

    res = minimize(objective, x0=total_wbtc/2, bounds=[(0, total_wbtc)])
    return res.x[0], -res.fun


def optimize_repayment(total_usdc_needed):
    # Proportional initial guess based on liquidity
    total_liq = DAI_UNI + DAI_SUSHI + USDC_UNI + USDC_SUSHI
    init_guess = [
        total_usdc_needed * (DAI_UNI / total_liq),
        total_usdc_needed * (DAI_SUSHI / total_liq),
        total_usdc_needed * (USDC_UNI / total_liq),
        total_usdc_needed * (USDC_SUSHI / total_liq)
    ]

    def objective(x):
        # Scale units to "millions" internally to help the solver with precision
        weth_uni_dai = getAmountIn(WETH_DAI_UNI, DAI_UNI, x[0])
        weth_sushi_dai = getAmountIn(WETH_DAI_SUSHI, DAI_SUSHI, x[1])
        weth_uni_usdc = getAmountIn(WETH_USDC_UNI, USDC_UNI, x[2])
        weth_sushi_usdc = getAmountIn(WETH_USDC_SUSHI, USDC_SUSHI, x[3])
        return weth_uni_dai + weth_sushi_dai + weth_uni_usdc + weth_sushi_usdc

    def constraint(x):
        usdc_from_dai = (x[0] + x[1]) * (1 - CURVE_FEE)
        usdc_direct = x[2] + x[3]
        return usdc_from_dai + usdc_direct - total_usdc_needed

    cons = {'type': 'eq', 'fun': constraint}
    bounds = [(0, DAI_UNI*0.5), (0, DAI_SUSHI*0.5), (0, USDC_UNI*0.5), (0, USDC_SUSHI*0.5)]
    
    # Use a smaller tolerance and more iterations
    res = minimize(objective, init_guess, method='SLSQP', bounds=bounds, constraints=cons, 
                   options={'ftol': 1e-12, 'maxiter': 1000})
    
    if not res.success:
        print("Warning: Solver did not converge!")
        
    return res.x, res.fun

wbtc_uni_split, total_weth_received = optimize_wbtc_to_weth(WBTC_RECEIVED)
repay_splits, min_weth_cost = optimize_repayment(USDC_TO_REPAY)

print(f"Uni:   {wbtc_uni_split:.8f} WBTC")
print(f"Sushi: {WBTC_RECEIVED - wbtc_uni_split:.8f} WBTC")
print(f"Total WETH Out: {total_weth_received:.18f}")

print(f"Path A (DAI Uni):   {repay_splits[0]:.18f}")
print(f"Path A (DAI Sushi): {repay_splits[1]:.18f}")
print(f"Path B (USDC Uni):  {repay_splits[2]:.18f}")
print(f"Path B (USDC Sushi):{repay_splits[3]:.18f}")
print(f"Total WETH Cost: {min_weth_cost:.18f}")

print(f"Estimated Profit: {total_weth_received - min_weth_cost:.18f} ETH")
