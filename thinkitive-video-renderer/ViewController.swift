import UIKit
import Photos

@available(iOS 11.0, *)
class ViewController: UIViewController {
    
    override func viewDidLoad() {
        super.viewDidLoad()
        
        let selectButton = UIButton(type: .system)
        selectButton.translatesAutoresizingMaskIntoConstraints = false
        selectButton.setTitle("Select Photo/Video", for: .normal)
        selectButton.addTarget(self, action: #selector(selectButtonTapped), for: .touchUpInside)
        
        view.addSubview(selectButton)
        NSLayoutConstraint.activate([
            selectButton.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            selectButton.centerYAnchor.constraint(equalTo: view.centerYAnchor)
        ])
    }
    
    @objc func selectButtonTapped() {
        let permissionManager = PhotosPermissionManager()
        if !permissionManager.hasPermission() {
            permissionManager.requestPermission { (granted) in
                DispatchQueue.main.async {
                    self.presentPhotosLibrary()
                }
            }
        } else {
            self.presentPhotosLibrary()
        }
    }
    
    private func presentPhotosLibrary() {
        if UIImagePickerController.isSourceTypeAvailable(.photoLibrary) {
            let myPickerController = UIImagePickerController()
            myPickerController.delegate = self;
            myPickerController.sourceType = .photoLibrary
            myPickerController.mediaTypes = ["public.movie", "public.image"]
            self.present(myPickerController, animated: true, completion: nil)
        }
    }
    
    private func exportVideoAsset(_ phAsset: PHAsset) {
        
        let lottieOverlay = LottieOverlayView(frame: CGRect(x: 0, y: 0, width: 300, height: 200),
                                              lottieIdentifier: "dino_data")
        
        self.view.addSubview(lottieOverlay)
        
        VideoRenderer.exportVideoAsset(phAsset: phAsset,
                                       duration: 5.0,
                                       resolution: CGSize(width: 1920, height: 1080),
                                       overlays: [lottieOverlay]) { [weak self] url, error in
            
            guard let url = url else {
                if let error = error {
                    let alert = UIAlertController(title: "Error", message: error.localizedDescription, preferredStyle: .alert)
                    self?.present(alert, animated: true)
                }
                return
            }
        
            VideoRenderer.saveVideoInPhotos(url: url) { [weak self] in
                let alert = UIAlertController(title: "Done", message: "Video saved in photos", preferredStyle: .alert)
                self?.present(alert, animated: true)
            }
        }
    }
}

@available(iOS 11.0, *)
extension ViewController: UIImagePickerControllerDelegate, UINavigationControllerDelegate {
    func imagePickerController(_ picker: UIImagePickerController, didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey : Any]) {        
        picker.dismiss(animated: true) { [weak self] in
            if let phAsset = info[UIImagePickerController.InfoKey.phAsset] as? PHAsset {
                self?.exportVideoAsset(phAsset)
            }
        }
    
    }
    
    func imagePickerControllerDidCancel(_ picker: UIImagePickerController) {
        picker.dismiss(animated: true, completion: nil)
    }
}
