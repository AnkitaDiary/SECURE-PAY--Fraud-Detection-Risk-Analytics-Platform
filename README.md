# SECURE-PAY--Fraud-Detection-Risk-Analytics-Platform# Credit Card Fraud Detection System

## Project Overview
This project is a machine learning-based credit card fraud detection system designed to identify potentially fraudulent transactions in real-time. The system uses XGBoost and Random Forest models, along with SMOTE, to handle class imbalance in transaction data. It provides a comprehensive pipeline, spanning from data preprocessing to model deployment and user interaction.

The project includes a Flask web application where users can input transaction details, which are then processed by the trained models to generate a fraud risk score. It also includes a frontend interface for easy interaction, and all preprocessing and model components are saved as `.pkl` files for seamless integration and reuse.

## Key Features
- **Real-time Fraud Detection:** Detects potential fraudulent transactions instantly through a Flask API.
- **Preprocessing Pipeline:** Ensures input data is cleaned and transformed consistently before prediction.
- **ML Models:** Uses XGBoost and Random Forest, trained on historical transaction data with class imbalance handled via SMOTE.
- **Frontend Interface:** Simple web-based interface for entering transaction details and viewing risk levels.
- **Model Configurations:** Saved configuration files ensure reproducibility of model predictions.

## File Structure
Credit-Card-Fraud-Detection/
├─ static/ # CSS, JS, images for the frontend
├─ templates/ # HTML templates (index.html)
├─ app_final1.py # Flask application for real-time prediction
├─ fraud_model_20251120_000910.pkl # Trained ML model
├─ preprocessor_20251120_000910.pkl # Data preprocessing pipeline
├─ model_config_20251120_000910.json # Model configuration details
├─ new1.ipynb # Jupyter notebook for data exploration and model training
├─ LOGO copy.png # Project logo
└─ README.md # Project overview and instructions


## Setup Instructions

1. **Clone the repository**
```bash
git clone <repository_url>
cd Credit-Card-Fraud-Detection
```
2.**Create a virtual environment (optional but recommended)
```
python -m venv venv
source venv/bin/activate       # Linux/Mac
venv\Scripts\activate          # Windows
```

3.**Install dependencies**
```
pip install -r requirements.txt
If you don't have a requirements.txt, you can install main libraries manually:
pip install flask pandas numpy scikit-learn xgboost
```
4.**Run the Flask app**
```
python app_final1.py
```

5.**Access the web interface**
```
Open your browser and go to:
http://127.0.0.1:5000/
Enter transaction details to get real-time fraud risk predictions.
```
