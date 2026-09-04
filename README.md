# ChargeMY

A Flutter-based EV charging application for Malaysia that brings together charging station discovery, journey planning, navigation, charging sessions, rewards, and account management in one platform.

## Features

- Nearby charging station discovery with availability updates, connector filters, and favourite stations
- Journey planning and charging-stop recommendations based on the user's EV profile
- Maps and navigation using OpenStreetMap, OSRM, Nominatim, and GPS location
- EV profile management with vehicle selection, battery details, and charging targets
- Simulated charging sessions with progress tracking and local notifications
- Charging payments through Stripe PaymentSheet in test mode
- Reward points, voucher redemption, charging history, and email payment receipts
- Email/password and email OTP authentication with profile management powered by Supabase
- Station ratings and hazard reports with photo evidence
- Admin tools for managing stations, charging piles, users, maintenance, rewards, and vouchers
- Revenue reports, utilization analytics, admin activity history, and CSV import/export
- Station location references from PLANMalaysia MEVnet, with simulated charging-pile data

## Installation

Clone the repository:

```bash
git clone https://github.com/weiluno/Mobile-Assignment.git ChargeMy
```

Navigate to the project directory:

```bash
cd ChargeMy
```

Install Flutter dependencies:

```bash
flutter pub get
```

Run the application:

```bash
flutter run
```
