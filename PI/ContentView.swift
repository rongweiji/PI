//
//  ContentView.swift
//  PI
//
//  Created by Rongwei Ji on 11/5/25.
//

import SwiftUI
import SwiftData

struct ContentView: View {
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 32) {
                    Text("Select a capture mode")
                        .font(.title2)
                        .fontWeight(.semibold)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.top, 24)

                    NavigationLink {
                        PhotoCaptureView()
                    } label: {
                        ModeButton(icon: "camera.fill", title: "Photo Capture", subtitle: "Capture still images with IMU snapshots")
                    }

                    NavigationLink {
                        VideoCaptureView()
                    } label: {
                        ModeButton(icon: "video.fill", title: "Video Capture", subtitle: "Record video and continuous IMU data")
                    }

                    NavigationLink {
                        IMUOnlyCaptureView()
                    } label: {
                        ModeButton(icon: "waveform.path.ecg", title: "IMU Only", subtitle: "Capture standalone IMU sessions and export CSV")
                    }

                    NavigationLink {
                        MotionPathView()
                    } label: {
                        ModeButton(icon: "figure.walk.circle", title: "Motion Visualizer", subtitle: "Realtime accelerometer path and distance")
                    }

                    NavigationLink {
                        ARMotionPathView()
                    } label: {
                        ModeButton(icon: "arkit", title: "AR Motion Visualizer", subtitle: "Use ARKit for higher precision tracking")
                    }
                }
                .padding(.horizontal)
                .padding(.bottom, 32)
            }
            .navigationTitle("PI Capture")
        }
    }
}

private struct ModeButton: View {
    let icon: String
    let title: String
    let subtitle: String

    var body: some View {
        HStack(alignment: .center, spacing: 16) {
            Image(systemName: icon)
                .font(.largeTitle)
                .foregroundColor(.white)
                .padding(18)
                .background(Color.blue)
                .clipShape(Circle())

            VStack(alignment: .leading, spacing: 6) {
                Text(title)
                    .font(.headline)
                Text(subtitle)
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.leading)
            }

            Spacer()
            Image(systemName: "chevron.right")
                .foregroundColor(.secondary)
        }
        .padding()
        .frame(maxWidth: .infinity)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(Color(.secondarySystemBackground))
        )
    }
}

#Preview {
    ContentView()
}
