import UIKit
import Photos
import thinkitive_video_renderer

class ViewController: UIViewController {
    
    weak var containerView: UIView?
    
    override func viewDidLoad() {
        super.viewDidLoad()
            
        let selectButton = UIButton(type: .system)
        selectButton.translatesAutoresizingMaskIntoConstraints = false
        selectButton.setTitle("Select Photo/Video", for: .normal)
        selectButton.addTarget(self, action: #selector(selectButtonTapped), for: .touchUpInside)
        
        let containerView = UIView()
        containerView.translatesAutoresizingMaskIntoConstraints = false
        containerView.backgroundColor = .gray // Use the color you want
        
        view.addSubview(containerView)
        view.addSubview(selectButton)
    
        self.containerView = containerView
        
        NSLayoutConstraint.activate([
            containerView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            containerView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            containerView.bottomAnchor.constraint(equalTo: selectButton.topAnchor, constant: -20),
            containerView.heightAnchor.constraint(equalToConstant: UIScreen.main.bounds.width),
            
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
        
        guard let containerView = containerView else {
            return
        }
        
        let width = CGFloat(phAsset.pixelWidth) / UIScreen.main.scale
        let height = CGFloat(phAsset.pixelHeight) / UIScreen.main.scale
        
        let lottieOverlay = LottieOverlayView(frame: CGRect(origin: CGPoint.zero,
                                                            size: CGSize(width: width, height:height)),
                                              lottieIdentifier: "dino_data")
        
        containerView.addSubview(lottieOverlay)
        
        VideoRenderer.exportVideoAsset(phAsset: phAsset,
                                       duration: 3.0,
                                       resolution: CGSize(width: width, height: height),
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
