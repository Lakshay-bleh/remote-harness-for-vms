# Razorpay checkout (razorpay_flutter)
-keepattributes *Annotation*
-dontwarn com.razorpay.**
-keep class com.razorpay.** {*;}
-optimizations !method/inlining/*
-keepclasseswithmembers class * {
  public void onPayment*(...);
}
-keep class proguard.annotation.** {*;}
-dontwarn proguard.annotation.**

# "Hey Escanor": Vosk talks to its native library through JNA, which finds classes and fields by name
-keep class com.sun.jna.** { *; }
-keep class * implements com.sun.jna.** { *; }
-keep class org.vosk.** { *; }
-dontwarn java.awt.**
-dontwarn com.sun.jna.**

# The phone side of the voice assistant, reached from the manifest and by name
-keep class com.escanorlabs.escanor.EscanorControlService { *; }
-keep class com.escanorlabs.escanor.WakeWordService { *; }
