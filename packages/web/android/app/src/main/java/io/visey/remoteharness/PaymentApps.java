package io.visey.remoteharness;

import java.util.Arrays;
import java.util.HashSet;
import java.util.Locale;
import java.util.Set;

/**
 * Payment, UPI, wallet and banking apps refuse to run (or warn "an app can see your screen") while any app has an accessibility
 * service switched on. Phone control switches itself off when one of them opens, so they keep working (see EscanorControlService).
 */
final class PaymentApps {
    private PaymentApps() {}

    private static final Set<String> KNOWN = new HashSet<>(Arrays.asList(
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
        "com.eg.android.AlipayGphone"
    ));

    /** Is this package a payment or banking app, by name or by what its package name says? */
    static boolean isPaymentApp(String pkg) {
        if (pkg == null || pkg.isEmpty()) return false;
        if (KNOWN.contains(pkg)) return true;
        String p = pkg.toLowerCase(Locale.ROOT);
        for (String part : p.split("[._]")) {
            if (part.contains("bank") || part.contains("wallet") || part.startsWith("pay") || part.endsWith("pay")) return true;
            if (part.equals("upi") || part.startsWith("upi") || part.endsWith("upi")) return true;
        }
        return false;
    }
}
