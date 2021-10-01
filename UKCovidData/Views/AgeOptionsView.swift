//
//  AgeOptionsView.swift
//  UKCovidData
//
//  Created by Joseph Lord on 28/09/2021.
//

import SwiftUI

struct AgeOptionsView: View {
    @ObservedObject var ageOptions: AgeOptions
    let showButtons: Bool
    
    var body: some View {
        VStack {
            if showButtons {
                HStack {
                    Button(action: {
                        ageOptions.setAll(enabled: true)
                    }, label: { Text("Enable All") })
                        .padding()
                        .border(Color.accentColor)
                    Spacer()
                    Button(action: {
                        ageOptions.setAll(enabled: false)
                    }, label: { Text("Disable All") })
                        .padding()
                        .border(Color.accentColor)
                }.padding()
            }
//            List() {
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 74, maximum: 120))]) {
                ForEach($ageOptions.options.indices, id: \.self) { index in
                    Toggle(
                        isOn: $ageOptions.options[index].isEnabled,
                        label: {
                            Text(ageOptions.options[index].age)
                        }
                    )
                }
                .toggleStyle(.button)
            }
        }
    }
}

struct AgeOptionsView_Previews: PreviewProvider {
    
    static var previews: some View {
        AgeOptionsView(ageOptions: AgeOptions(), showButtons: true)
    }
}
