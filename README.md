# Multi-Touch Marketing Attribution & Budget Optimizer

## Executive Summary
This project delivers a scalable, end-to-end analytics framework designed to map the multi-touch customer journey, accurately attribute revenue across all marketing touchpoints, and forecast future revenue trends. By transitioning from reactive, siloed reporting to proactive, data-driven modeling, this framework provides executive leadership with the clarity needed to optimize a $107.39K marketing budget, revealing massive optimization opportunities to improve the current 1.53 ROAS.

## 1. The Business Problem
### The Background
The company invests a significant monthly budget across multiple digital marketing channels (Google Ads, Facebook, Email, Organic) to drive customer acquisition. While top-of-funnel metrics are tracked, resulting in a baseline conversion rate of 2.02%, the connective tissue to long-term value is missing.

### The Complication (The Pain Point)
Currently, the marketing team measures success in silos, relying on simplistic First-Touch or Last-Touch attribution models. This creates a distorted view of performance:  
Misallocated Budget: Channels that assist in the middle of the customer journey are undervalued, while channels that happen to close the sale get disproportionate credit.  
Short-Term Myopia: The team evaluates against immediate purchases rather than underlying time-based trends.  
Data Fragmentation: Campaign spend data is isolated from customer journey touchpoints, making it impossible to see the true, blended Return on Ad Spend (ROAS).

### The Objective
To develop a unified data model that solves data fragmentation, applies advanced algorithmic attribution (Time-Decay), and utilizes a predictive layer to forecast revenue trends, ultimately empowering decision-makers to shift budgets toward high-value acquisition.

## 2. Project Architecture & Technical Execution

###  Phase 1: The Data Engine (SQL Server)
**The Business Goal:** Solve Data Fragmentation and Simplistic Attribution.  

An automated SQL pipeline utilizing Window Functions and Common Table Expressions (CTEs) was built to clean raw data and construct a unified view of the customer journey.  

Data Standardization: Implemented dimension mapping tables (dim_Channel_Mapping, dim_Country_Mapping) to categorize channels and standardize geographic inputs.  
LTV Calculation: Aggregated historical orders into a vw_customer_ltv view to shift focus from first-purchase value to true customer value.  
Multi-Touch Attribution (MTA): The customer_journey view chronologically tracks every interaction, calculating four simultaneous models:  
First-Touch: Rewards brand discovery.  
Last-Touch: Rewards the final closing channel.  
Linear: Distributes credit equally across the journey.  
Time-Decay (Primary): Utilizes an exponential decay function to give heavier credit to touchpoints closer to the conversion event.  
Final Aggregation: Merged daily ad spend with mathematically attributed revenue via a FULL OUTER JOIN, creating a pristine dataset for BI and predictive modeling.  

###  Phase 2: The Predictive Layer (Python)
**The Business Goal:** Solve Short-Term Myopia via Time-Series Forecasting.  

To project future performance, a univariate time-series forecasting model was developed (pandas, scikit-learn).  

Diagnostic Analysis & Model Pivot: Initial multivariate models attempted to correlate daily_spend with revenue. However, scatter plot diagnostics (Spend vs. Revenue) revealed a near-zero correlation due to heavy attribution lags and organic baseline revenue. Consequently, the model was pivoted to a pure Time-Series approach.  

Feature Engineering & Algorithm: Trained a LinearRegression model strictly on an engineered days variable to capture underlying revenue momentum.  

Constraint Enforcement: Applied a ReLU-like clamp (np.maximum(0, model.predict(...))) to prevent the model from projecting illogical negative revenue.  

###  Phase 3: The Decision Intelligence Layer (Power BI)
**The Business Goal:** Democratize insights and highlight budget inefficiencies.  

The data was visualized into a comprehensive 3-page interactive dashboard:  
Executive Overview: High-level KPIs (Total Revenue, Budget, Blended ROAS) and daily spend vs. return trending.  
Channel Attribution: A deep-dive matrix comparing First Touch, Last Touch, and Time Decay models side-by-side to expose the true ROI of each channel.  
Revenue Forecast: A 30-day forward-looking projection integrating the Python machine learning outputs directly into the BI environment.  

<img width="886" height="491" alt="image" src="https://github.com/user-attachments/assets/fc21c151-bbe8-4c44-afc6-b5a3c7dfc25f" />

<img width="890" height="496" alt="image" src="https://github.com/user-attachments/assets/3db2b20c-fdcc-4d80-a122-d3ff9bb01817" />

<img width="892" height="489" alt="image" src="https://github.com/user-attachments/assets/6a87c21a-01fe-449c-b143-a9568b1b5740" />


## 3. Key Findings & Business Recommendations

Based on the final data models and Power BI visualization, several critical insights were uncovered:

 Insight 1: The Facebook Budget Drain  
The Data: Out of the $107.39K total budget, a massive $66.2K was allocated to Facebook.  
The Reality: Under the Time-Decay attribution model, Facebook only generated $45.3K in revenue, resulting in a 0.69 ROAS. The company is losing money on this channel, yet it commands the vast majority of the budget.  

 Insight 2: Underfunded High-Performers  
The Data: Email and Google Ads receive significantly less funding but yield massive returns.  
The Reality: * Email: Spent $6.4K → Generated $36.9K (Time-Decay) = 5.77 ROAS  
Google Ads: Spent $11.9K → Generated $53.3K (Time-Decay) = 4.47 ROAS  
Both channels are highly efficient at driving multi-touch conversions but are being starved of capital.  

 Insight 3: The Forward-Looking Revenue Slump  
The Data: The Time-Series Python model calculated a "Time Trend Coefficient" of -$5.52.  
The Reality: Historical data shows a sharp decline in revenue from March through May. The 30-day predictive model forecasts that without intervention, revenue will continue to stagnate, projecting only $17.04K over the next month (averaging $568/day).  

🎯 Final Strategic Recommendation  
Halt the current budget allocation immediately. The company must drastically reduce the Facebook ad spend and reallocate those funds into scaling the Google Ads campaigns and expanding Email marketing capture efforts. Doing so will optimize the overall CAC, improve the blended 1.53 ROAS, and reverse the negative daily revenue trend projected by the forecasting model.
