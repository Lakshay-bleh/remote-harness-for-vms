package com.escanorlabs.escanor

import java.util.Locale

/**
 * Payment, UPI, wallet and banking apps refuse to run (or warn "an app can see your screen") while any app has an accessibility
 * service switched on. Phone control switches itself off when one of them opens, so they keep working (see EscanorControlService).
 */
internal object PaymentApps {
    private val KNOWN: Set<String> = hashSetOf(
        // India: UPI and wallets
        "com.google.android.apps.nbu.paisa.user", // Google Pay
        "com.phonepe.app",
        "net.one97.paytm",
        "in.org.npci.upiapp", // BHIM
        "com.dreamplug.androidapp", // CRED
        "com.mobikwik_new",
        "com.freecharge.android",
        "money.super.payments", // super.money
        "com.naviapp",
        "in.juspay.hyperupi",
        // India: banks
        "com.sbi.lotusintouch", // YONO SBI
        "com.sbi.upi",
        "com.snapwork.hdfc",
        "com.hdfcbank.payzapp",
        "com.csam.icici.bank.imobile",
        "com.axis.mobile",
        "com.msf.kbank.mobile", // Kotak
        "com.fss.pnbone",
        "com.bankofbaroda.mconnect",
        "com.infrasofttech.indianBank",
        "com.canarabank.mobility",
        "com.unionbankofindia.vyom",
        "com.idfcfirstbank.optimus",
        "com.indusind.indie",
        "com.fedbank.fedmobile",
        "com.yesbank",
        "com.airtel.money",
        // Elsewhere
        "com.google.android.apps.walletnfcrel", // Google Wallet
        "com.samsung.android.spay", // Samsung Wallet
        "com.paypal.android.p2pmobile",
        "com.venmo",
        "com.squareup.cash",
        "com.zellepay.zelle",
        "com.revolut.revolut",
        "com.transferwise.android", // Wise
        "com.chase.sig.android",
        "com.wf.wellsfargomobile",
        "com.infonow.bofa",
        "com.konylabs.capitalone",
        "com.citi.citimobile",
        "com.usaa.mobile.android.usaa",
        "com.barclays.android.barclaysmobilebanking",
        "uk.co.hsbc.hsbcukmobilebanking",
        "com.grppl.android.shell.CMBlloydsTSB73", // Lloyds
        "com.monzo.android",
        "com.starlingbank.android",
        "de.number26.android", // N26
        "com.klarna.android",
        "com.mercadopago.wallet",
        "com.nu.production", // Nubank
        "com.eg.android.AlipayGphone",
    )

    private val PARTS = Regex("[._]")

    /** Is this package a payment or banking app, by name or by what its package name says? */
    @JvmStatic
    fun isPaymentApp(pkg: String?): Boolean {
        if (pkg.isNullOrEmpty()) return false
        if (pkg in KNOWN) return true
        val p = pkg.lowercase(Locale.ROOT)
        for (part in p.split(PARTS)) {
            if (part.contains("bank") || part.contains("wallet") || part.startsWith("pay") || part.endsWith("pay")) return true
            if (part == "upi" || part.startsWith("upi") || part.endsWith("upi")) return true
        }
        return false
    }
}
