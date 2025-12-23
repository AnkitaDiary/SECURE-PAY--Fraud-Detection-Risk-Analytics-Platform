from flask import Flask, request, jsonify, render_template
import pickle
import pandas as pd
import numpy as np
import json
import sys
from datetime import datetime
import mysql.connector

# ---------------- DATABASE CONFIG ----------------
def get_db_connection():
    return mysql.connector.connect(
        host='127.0.0.1',
        user='root',
        password='xyz*',
        database='credit_card_database',
        port=3306
    )

# ---------------- FIX WINDOWS ENCODING ----------------
if sys.platform == 'win32':
    import codecs
    sys.stdout = codecs.getwriter('utf-8')(sys.stdout.buffer, 'strict')
    sys.stderr = codecs.getwriter('utf-8')(sys.stderr.buffer, 'strict')

app = Flask(__name__)

# ---------------- CONFIGURATION ----------------
TIMESTAMP = "20251120_000910"
MODEL_PATH = r"fraud_model_20251120_000910.pkl"
PREPROCESS_PATH = r"preprocessor_20251120_000910.pkl"
CONFIG_PATH = r"model_config_20251120_000910.json"

# ---------------- LOAD MODEL & PREPROCESSORS ----------------
try:
    with open(MODEL_PATH, 'rb') as f:
        model = pickle.load(f)
    with open(PREPROCESS_PATH, 'rb') as f:
        preprocessors = pickle.load(f)
    with open(CONFIG_PATH, 'r') as f:
        config = json.load(f)
    print("[OK] Model, preprocessor, and config loaded")
except Exception as e:
    print(f"[ERROR] {e}")
    sys.exit(1)

# ---------------- LOOKUP DICTIONARIES ----------------
BANK_TO_ID = {
    'ICICI Bank': 'B001', 'SBI': 'B002', 'HDFC Bank': 'B003', 'Federal Bank': 'B004',
    'Andhra Bank': 'B005', 'Bank of Baroda': 'B006', 'Yes Bank': 'B007',
    'Kotak Bank': 'B008', 'Axis Bank': 'B009'
}

MERCHANT_TO_ID = {
    'Uber': 'M001', 'Zomato': 'M002', 'Myntra': 'M003', 'Lifestyle': 'M004',
    'Tata Cliq': 'M005', 'Flipkart': 'M006', 'Amazon India': 'M007',
    'Big Bazaar': 'M008', 'Reliance Digital': 'M009', 'Swiggy': 'M010'
}

MERCHANT_STATES = {
    merchant: ['Ahmedabad','Bangalore','Chennai','Delhi','Hyderabad','Jaipur','Kochi','Kolkata','Lucknow','Mumbai']
    for merchant in MERCHANT_TO_ID.keys()
}

# ---------------- HELPER FUNCTIONS ----------------
def preprocess_input(data_dict):
    df = pd.DataFrame([data_dict])
    feature_columns = preprocessors['feature_columns']

    for col in feature_columns:
        if col not in df.columns:
            df[col] = 0

    df = df[feature_columns]
    label_encoders = preprocessors['label_encoders']
    categorical_cols = preprocessors['categorical_cols']

    for col in categorical_cols:
        if col in df.columns:
            le = label_encoders[col]
            try:
                df[col] = le.transform(df[col].astype(str))
            except:
                df[col] = 0

    scaler = preprocessors['scaler']
    numeric_cols = preprocessors['numeric_cols']
    if numeric_cols:
        df[numeric_cols] = scaler.transform(df[numeric_cols])

    return df

def assign_fraud_level(fraud_prob):
    fraud_score = int(fraud_prob * 100)
    if fraud_score <= 30:
        return fraud_score, 'LOW'
    elif fraud_score <= 60:
        return fraud_score, 'MEDIUM'
    elif fraud_score <= 80:
        return fraud_score, 'HIGH'
    else:
        return fraud_score, 'CRITICAL'

def get_recommendation(fraud_level):
    recommendations = {
        'LOW': 'Low risk. Transaction appears normal. Proceed with approval.',
        'MEDIUM': 'Medium risk. Monitor transaction or request additional authentication.',
        'HIGH': 'High risk. Strong user verification recommended before approval.',
        'CRITICAL': 'Critical risk. Block transaction immediately and investigate fraud.'
    }
    return recommendations.get(fraud_level, 'Unknown risk level')

# ---------------- FLASK ROUTES ----------------
@app.route('/')
def index():
    return render_template("index.html")

@app.route('/predict', methods=['POST'])
def predict():
    try:
        bank_name = request.form.get('bank')
        merchant_name = request.form.get('merchant_name')
        merchant_state = request.form.get('merchant_state')

        # --- VALIDATION ---
        if bank_name not in BANK_TO_ID:
            return jsonify({'error': f'Invalid bank: {bank_name}'}), 400
        if merchant_name not in MERCHANT_TO_ID:
            return jsonify({'error': f'Invalid merchant: {merchant_name}'}), 400
        if merchant_state not in MERCHANT_STATES.get(merchant_name, []):
            return jsonify({'error': f'Invalid state "{merchant_state}" for merchant "{merchant_name}"'}), 400

        bank_id = BANK_TO_ID[bank_name]
        merchant_id = MERCHANT_TO_ID[merchant_name]

        data_dict = {
            'Customer Name': request.form.get('customer_name'),
            'Customer State': request.form.get('customer_state'),
            'Transaction Category': request.form.get('category'),
            'Card Type': request.form.get('card_type'),
            'BANK ID': bank_id,
            'Bank': bank_name,
            'Merchant Id': merchant_id,
            'Merchant Name': merchant_name,
            'merchant_state': merchant_state,
            'Transaction Amount': float(request.form.get('amount')),
            'Transaction Hour': int(request.form.get('hour')),
            'Card Present': int(request.form.get('card_present')),
            'International': int(request.form.get('international'))
        }

        # --- PREPROCESS & PREDICT ---
        input_df = preprocess_input(data_dict)
        fraud_prob = float(model.predict_proba(input_df.values)[0][1])
        fraud_score, fraud_level = assign_fraud_level(fraud_prob)
        is_fraud = 1 if fraud_score > 50 else 0
        recommendation = get_recommendation(fraud_level)

        # --- SAVE TO DATABASE ---
        try:
            conn = get_db_connection()
            cursor = conn.cursor()
            cursor.callproc('add_new_transaction', [
                data_dict['Customer Name'],
                data_dict['Customer State'],
                bank_id,
                merchant_id,
                merchant_state,
                datetime.now(),
                data_dict['Transaction Amount'],
                data_dict['Transaction Category'],
                data_dict['Card Type'],
                is_fraud,
                fraud_score,
                fraud_level,
                data_dict['Transaction Hour'],
                data_dict['Card Present'],
                data_dict['International']
            ])
            conn.commit()
            print("[DB] Transaction saved successfully.")
        except mysql.connector.Error as e:
            print(f"[MYSQL ERROR] {e}")
            raise
        finally:
            cursor.close()
            conn.close()

        return jsonify({
            'fraud_score': int(fraud_score),
            'fraud_level': fraud_level,
            'is_fraud': is_fraud,
            'recommendation': recommendation,
            'fraud_probability': round(fraud_prob, 4)
        })

    except Exception as e:
        print(f"[ERROR] {e}")
        import traceback
        traceback.print_exc()
        return jsonify({'error': str(e)}), 400

@app.route('/health')
def health():
    return jsonify({
        'status': 'healthy',
        'model': config['model_name'],
        'f1_score': config['test_f1_score']
    })

# ---------------- RUN SERVER ----------------
if __name__ == '__main__':
    print("Starting Flask server at http://localhost:5000")
    app.run(host='0.0.0.0', port=5000, debug=True)
