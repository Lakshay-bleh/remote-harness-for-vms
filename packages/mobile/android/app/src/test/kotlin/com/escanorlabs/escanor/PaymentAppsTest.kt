package com.escanorlabs.escanor

import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

class PaymentAppsTest {

    @Test
    fun knownPaymentApps() {
        assertTrue(PaymentApps.isPaymentApp("com.google.android.apps.nbu.paisa.user")) // Google Pay India
        assertTrue(PaymentApps.isPaymentApp("com.phonepe.app"))
        assertTrue(PaymentApps.isPaymentApp("net.one97.paytm"))
        assertTrue(PaymentApps.isPaymentApp("in.org.npci.upiapp")) // BHIM
        assertTrue(PaymentApps.isPaymentApp("com.sbi.lotusintouch")) // YONO SBI
        assertTrue(PaymentApps.isPaymentApp("com.dreamplug.androidapp")) // CRED
        assertTrue(PaymentApps.isPaymentApp("com.squareup.cash"))
    }

    @Test
    fun namesThatSayBankOrPay() {
        assertTrue(PaymentApps.isPaymentApp("com.example.mybank"))
        assertTrue(PaymentApps.isPaymentApp("com.bankofsomewhere.mobile"))
        assertTrue(PaymentApps.isPaymentApp("com.example.paywallet"))
        assertTrue(PaymentApps.isPaymentApp("com.example.upi"))
    }

    @Test
    fun ordinaryApps() {
        assertFalse(PaymentApps.isPaymentApp(null))
        assertFalse(PaymentApps.isPaymentApp(""))
        assertFalse(PaymentApps.isPaymentApp("com.escanorlabs.escanor")) // Escanor itself
        assertFalse(PaymentApps.isPaymentApp("io.visey.remoteharness")) // the old app id
        assertFalse(PaymentApps.isPaymentApp("com.android.systemui"))
        assertFalse(PaymentApps.isPaymentApp("com.google.android.youtube"))
        assertFalse(PaymentApps.isPaymentApp("com.android.vending")) // Play Store
        assertFalse(PaymentApps.isPaymentApp("com.example.displaytools"))
        assertFalse(PaymentApps.isPaymentApp("com.example.cupid")) // "upi" inside a word is not UPI
        assertFalse(PaymentApps.isPaymentApp("com.example.player"))
    }
}
