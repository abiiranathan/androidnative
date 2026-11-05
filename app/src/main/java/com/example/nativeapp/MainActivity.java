package com.example.nativeapp;
    
import android.app.Activity;
import android.os.Build;
import android.os.Bundle;
import android.widget.TextView;

/** Minimal activity that displays a string produced by the C library. */
public class MainActivity extends Activity {
    @Override
    protected void onCreate(Bundle savedInstanceState) {
        super.onCreate(savedInstanceState);

        String abi = Build.SUPPORTED_ABIS.length > 0 ? Build.SUPPORTED_ABIS[0] : "unknown";
        String message = NativeGreeting.format("Android")
                + "\n\nABI: " + abi
                + "\nAPI level: " + Build.VERSION.SDK_INT;

        TextView view = new TextView(this);
        view.setTextSize(24f);
        view.setPadding(48, 48, 48, 48);
        view.setText(message);
        setContentView(view);
    }
}
