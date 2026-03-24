import numpy as np
from scipy.optimize import minimize, minimize_scalar

liqBonus = 1.1
WBTCin = 94.27338222
DAIout = 2920000

WETHuni = 38844.42475154482370337
WBTCuni = 2293.69102880
WETHsushi = 88902.650478574486113986
WBTCsushi = 5253.97180491

WETHuni1 = 25620.287386779241095276
DAIuni1 = 51680858.415802498210642391
WETHsushi1 = 50672.987628912073722125
DAIsushi1 = 102278491.801378063064041805

WETHuni2 = 53146.035951023773605158
USDCuni2 = 107391732.922008
WETHsushi2 = 82306.099800901231324544
USDCsushi2 = 166057035.198029

pools1 = [
    [WBTCuni, WETHuni],
    [WBTCsushi, WETHsushi]
]

pools2 = [
    [WETHuni1, DAIuni1],
    [WETHsushi1, DAIsushi1],
    [WETHuni2, USDCuni2],
    [WETHsushi2, USDCsushi2]
]

def getAmountIn(rIn, rOut, dy):
    # given amountOut, give amountIn
    num = rIn * dy
    den = (rOut - dy) * .997
    return num / den

def getAmountOut(rIn, rOut, dx):
    # given amountIn, give amountOut
    dxFee = dx * .997
    num = dxFee * rOut
    den = rIn + dxFee
    return num / den

def optimiseSplitOut(totalIn, pools):
    def objective(x):
        totalOut = -sum(getAmountOut(pools[i][0], pools[i][1], x[i]) for i in range(len(x)))
        return totalOut

    cons = ({'type': 'eq', 'fun': lambda x: sum(x) - totalIn})
    bounds = [(0, totalIn) for _ in pools]
    init_guess = [totalIn / len(pools)] * len(pools)

    res = minimize(objective, init_guess, method="SLSQP", bounds=bounds, constraints=cons)

    return res

def optimiseSplitIn(totalOut, pools):
    # y0 is the USDT taken from pool 0. Pool 1 takes the rest.
    def objective(y0):
        y1 = totalOut - y0
        return getAmountIn(pools[0][0], pools[0][1], y0) + getAmountIn(pools[1][0], pools[1][1], y1)

    # Ensure we don't drain more than 99% of either pool
    max_y0 = min(totalOut, pools[0][1] * 0.99)
    min_y0 = max(0, totalOut - pools[1][1] * 0.99)

    res = minimize_scalar(objective, bounds=(min_y0, max_y0), method='bounded')
    
    usdt_split = [res.x, totalOut - res.x]
    weth_split = [
        getAmountIn(pools[0][0], pools[0][1], usdt_split[0]), 
        getAmountIn(pools[1][0], pools[1][1], usdt_split[1])
    ]
    
    return usdt_split, weth_split

# Execution
usdt_split, weth_split = optimiseSplitIn(DAIout, pools2)
print("Optimal DAI split:", usdt_split)
print("Optimal WETH in:", weth_split)
print("Total WETH required:", sum(weth_split))

res = optimiseSplitOut(WBTCin, pools1)
print(res)
print(res["x"])

print(getAmountOut(WBTCsushi, WETHsushi, WBTCin))

# res = optimiseSplitIn(USDTout, pools2)
# print(res)
# print(res["x"])
# print(sum(res["x"]))